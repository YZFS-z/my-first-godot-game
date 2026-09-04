"""
自定义资源管理器（载具/地图）
存储玩家上传的自定义资源，支持下载分发和哈希校验
"""
import os
import json
import hashlib

RESOURCE_DIR = os.path.join(os.path.dirname(__file__), "data", "custom_resources")
HASH_DIR = os.path.join(os.path.dirname(__file__), "data", "resource_hashes")


class ResourceManager:
    def __init__(self):
        os.makedirs(os.path.join(RESOURCE_DIR, "vehicles"), exist_ok=True)
        os.makedirs(os.path.join(RESOURCE_DIR, "maps"), exist_ok=True)
        os.makedirs(os.path.join(HASH_DIR, "vehicles"), exist_ok=True)
        os.makedirs(os.path.join(HASH_DIR, "maps"), exist_ok=True)

    def _get_path(self, resource_type: str, resource_id: str) -> str:
        """获取资源文件路径"""
        safe_id = resource_id.replace("/", "_").replace("\\", "_")
        if resource_type == "vehicle":
            return os.path.join(RESOURCE_DIR, "vehicles", f"{safe_id}.json")
        elif resource_type == "map":
            return os.path.join(RESOURCE_DIR, "maps", f"{safe_id}.json")
        return None

    def _get_hash_path(self, resource_type: str, resource_id: str) -> str:
        """获取资源哈希文件路径"""
        safe_id = resource_id.replace("/", "_").replace("\\", "_")
        if resource_type == "vehicle":
            return os.path.join(HASH_DIR, "vehicles", f"{safe_id}.hash")
        elif resource_type == "map":
            return os.path.join(HASH_DIR, "maps", f"{safe_id}.hash")
        return None

    @staticmethod
    def compute_hash(data: dict) -> str:
        """计算资源数据的SHA-256哈希"""
        # 排序键名确保一致性，去除source字段（因为下载后会自动添加）
        clean_data = {k: v for k, v in sorted(data.items()) if k != "source"}
        json_str = json.dumps(clean_data, sort_keys=True, ensure_ascii=False)
        return hashlib.sha256(json_str.encode("utf-8")).hexdigest()

    def exists(self, resource_type: str, resource_id: str) -> bool:
        """检查资源是否存在"""
        path = self._get_path(resource_type, resource_id)
        if path is None:
            return False
        return os.path.exists(path)

    def get(self, resource_type: str, resource_id: str) -> dict:
        """获取资源数据"""
        path = self._get_path(resource_type, resource_id)
        if path is None or not os.path.exists(path):
            return {}
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            return {}

    def get_hash(self, resource_type: str, resource_id: str) -> str:
        """获取资源的存储哈希"""
        hash_path = self._get_hash_path(resource_type, resource_id)
        if hash_path is None or not os.path.exists(hash_path):
            return ""
        try:
            with open(hash_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except IOError:
            return ""

    def verify_hash(self, resource_type: str, resource_id: str, client_hash: str) -> bool:
        """校验客户端资源哈希是否与服务器存储的一致"""
        server_hash = self.get_hash(resource_type, resource_id)
        if not server_hash:
            return False  # 服务器无此资源，校验失败
        return server_hash == client_hash

    def save(self, resource_type: str, resource_id: str, data: dict, client_hash: str = "") -> dict:
        """保存资源数据，同时存储哈希。返回 {success, message, hash}"""
        path = self._get_path(resource_type, resource_id)
        if path is None:
            return {"success": False, "message": "不支持的资源类型", "hash": ""}
        try:
            # 确保标记为自定义来源
            if "source" not in data:
                data["source"] = "custom"
            if "id" not in data:
                data["id"] = resource_id
            # 计算服务器端哈希（作为该资源的权威哈希，供下载方校验）
            server_hash = self.compute_hash(data)
            # 注意：不校验客户端哈希，因为客户端和服务器JSON序列化方式可能不同
            # 自定义资源只要房间内玩家从同一服务器下载，哈希自然一致
            # 保存资源数据
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            # 保存哈希
            hash_path = self._get_hash_path(resource_type, resource_id)
            with open(hash_path, "w", encoding="utf-8") as f:
                f.write(server_hash)
            print(f"[ResourceManager] 资源已保存: {resource_type}/{resource_id}, hash={server_hash[:16]}...")
            return {"success": True, "message": "上传成功", "hash": server_hash}
        except IOError as e:
            print(f"[ResourceManager] 保存失败: {e}")
            return {"success": False, "message": f"保存失败: {e}", "hash": ""}

    def list_all(self, resource_type: str) -> list:
        """列出所有指定类型的资源"""
        if resource_type == "vehicle":
            dir_path = os.path.join(RESOURCE_DIR, "vehicles")
        elif resource_type == "map":
            dir_path = os.path.join(RESOURCE_DIR, "maps")
        else:
            return []
        if not os.path.exists(dir_path):
            return []
        return [f.replace(".json", "") for f in os.listdir(dir_path) if f.endswith(".json")]


# 全局单例
resource_manager = ResourceManager()
