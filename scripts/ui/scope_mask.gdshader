shader_type canvas_item;

// 炮镜圆形遮罩：圆外黑色，圆内透明
uniform float radius_ratio : hint_range(0.1, 0.9) = 0.45;

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	// 校正宽高比：uv.x *= width/height，确保正圆
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(uv);
	if (dist < radius_ratio) {
		discard; // 圆内透明，显示3D场景
	}
	COLOR = vec4(0.0, 0.0, 0.0, 1.0); // 圆外黑色
}
