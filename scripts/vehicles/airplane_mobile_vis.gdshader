shader_type spatial;
render_mode cull_back;

// 飞机专用移动端可见性增强：解决手机端深色机体与暗背景融合看不清的问题。
// 相比通用 mobile_rim.gdshader，增强了三点：
//   1. 全模型基础自发光(base_emission)：不只是边缘，整个机体有最小亮度，暗环境不消失
//   2. 更强的边缘轮廓光(rim)：勾勒清晰外形
//   3. 显式 PBR 参数(roughness/metallic)：改善 Mobile 渲染器光照响应
// 仅在手机模式由 airplane.gd 覆盖应用，桌面端零影响。
uniform vec4 base_color : source_color = vec4(0.6, 0.65, 0.7, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float rim_strength : hint_range(0.0, 6.0) = 3.0;
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;
uniform float base_emission : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.65;
uniform float metallic : hint_range(0.0, 1.0) = 0.15;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	// 边缘轮廓光：法线偏离视线的片元叠加暖白自发光
	float facing = clamp(dot(normalize(NORMAL), normalize(-VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	// 基础自发光 + 边缘增强，确保暗环境下机体整体可辨、边缘清晰
	EMISSION = base_color.rgb * base_emission + rim_color.rgb * rim * rim_strength;
}
