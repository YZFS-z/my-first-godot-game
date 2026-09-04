shader_type spatial;
render_mode cull_back;

// 手机模式机体轮廓发光：法线偏离视线（机体边缘）的片元叠加暖白轮廓自发光(EMISSION)。
// 目的：深色机体在低对比度背景/暗屏上与天空地面融合看不清轮廓（用户反馈"只能看到昵称
// 看不到机体"），轮廓光不依赖光源、暗环境同样生效，让机体边缘勾勒出清晰外形。
// 保留原材质基色(base_color 由代码从原材质拷贝)与场景光照；移动端开销为简单片元计算。
uniform vec4 base_color : source_color = vec4(0.55, 0.6, 0.65, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.8;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;

void fragment() {
	ALBEDO = base_color.rgb;
	float facing = clamp(dot(normalize(NORMAL), normalize(-VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	EMISSION = rim_color.rgb * rim * rim_strength;
}