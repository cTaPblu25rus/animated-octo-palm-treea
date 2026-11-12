// Пиксельный стиль: картинка 3D-сцены собирается в крупные пиксели,
// цвета сводятся к ограниченной палитре с упорядоченным дизерингом (матрица Байера 4×4).
// Один проход по экрану, без циклов — дёшево для телефона.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float pixel_size = 4.0;   // размер «пикселя» в пикселях экрана
uniform float levels = 6.0;       // оттенков на канал
uniform float dither = 0.6;

const mat4 BAYER = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0));

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(SCREEN_UV * res / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size / res;
	vec3 c = texture(screen_tex, uv).rgb;
	// Чуть поднять насыщенность: палитра выглядит сочнее
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.25);
	int bx = int(mod(cell.x, 4.0));
	int by = int(mod(cell.y, 4.0));
	float threshold = (BAYER[bx][by] / 16.0 - 0.5) * dither / levels;
	c = floor(clamp(c + threshold, 0.0, 1.0) * levels + 0.5) / levels;
	COLOR = vec4(c, 1.0);
}
