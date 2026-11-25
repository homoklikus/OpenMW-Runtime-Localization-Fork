extends RefCounted
## Kursory gry jak OpenMW 0.51 (openmw_pointer.xml, openmw_resources.xml; WindowManager::createCursors →
## SDLCursorManager::createCursor): tekstura z danych gry przeskalowana do rozmiaru wskaźnika 32 × 32, obrócona
## (SDL_RenderCopyEx z kątem −Rotation, wokół środka), punkt aktywny z Point.
##   arrow       tx_cursor.dds            (7, 0)               – zwykły wskaźnik
##   hresize     tx_cursormove.dds        (16, 14)  0°         – krawędź lewa/prawa okna
##   vresize     tx_cursormove.dds        (17, 16)  90°        – krawędź górna/dolna
##   dresize     tx_cursormove.dds        (17, 15)  −45°       – róg lewy górny / prawy dolny
##   dresize2    tx_cursormove.dds        (15, 15)  45°        – róg prawy górny / lewy dolny
##   drop_ground cursor_drop_ground.dds   (0, 24)              – przedmiot przy kursorze nad światem, gdy nie da się
##                                                                go postawić w punkcie kursora (HUD::onWorldMouseOver)
## Odpowiedniki kształtów Godota: ARROW, HSIZE, VSIZE, FDIAGSIZE, BDIAGSIZE, CAN_DROP.

const SIZE := 32
const POINTERS := [
	["arrow", "textures/tx_cursor", Vector2i(7, 0), 0.0, Input.CURSOR_ARROW],
	["hresize", "textures/tx_cursormove", Vector2i(16, 14), 0.0, Input.CURSOR_HSIZE],
	["vresize", "textures/tx_cursormove", Vector2i(17, 16), 90.0, Input.CURSOR_VSIZE],
	["dresize", "textures/tx_cursormove", Vector2i(17, 15), -45.0, Input.CURSOR_FDIAGSIZE],
	["dresize2", "textures/tx_cursormove", Vector2i(15, 15), 45.0, Input.CURSOR_BDIAGSIZE],
	["drop_ground", "textures/cursor_drop_ground", Vector2i(0, 24), 0.0, Input.CURSOR_CAN_DROP],
]

static var applied := {}            # nazwa wskaźnika → kształt Godota (testy, diagnostyka)

## Ustawia kursory z katalogu danych (PNG z konwersji). Brak tekstury – kursor systemowy dla tego kształtu.
static func apply(data_root: String) -> int:
	applied.clear()
	if DisplayServer.get_name() == "headless":
		return 0
	for p in POINTERS:
		var img := pointer_image(data_root, String(p[1]), float(p[3]))
		if img == null:
			continue
		Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), int(p[4]), p[2])
		applied[String(p[0])] = int(p[4])
	return applied.size()

## Obraz wskaźnika: tekstura przeskalowana do 32 × 32 (filtr liniowy – SDL_HINT_RENDER_SCALE_QUALITY 1) i obrócona
## zgodnie z ruchem wskazówek zegara o −rot stopni (SDL_RenderCopyEx: kąt −Rotation).
static func pointer_image(data_root: String, rel: String, rot: float) -> Image:
	var path := data_root.path_join(rel + ".png")
	if data_root.is_empty() or not FileAccess.file_exists(path):
		return null
	var src := Image.load_from_file(path)
	if src == null or src.is_empty():
		return null
	src.convert(Image.FORMAT_RGBA8)
	if src.get_width() != SIZE or src.get_height() != SIZE:
		src.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	if is_zero_approx(rot):
		return src
	return rotated(src, -rot)

## Obrót obrazu o kąt (stopnie, zgodnie z ruchem wskazówek zegara na ekranie) wokół środka, próbkowanie dwuliniowe,
## poza obrazem – przezroczystość.
static func rotated(src: Image, deg: float) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var a := deg_to_rad(deg)
	var c := cos(a)
	var s := sin(a)
	var cx := w / 2.0
	var cy := h / 2.0
	for y in h:
		for x in w:
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var sx := dx * c + dy * s + cx - 0.5          # odwrotność obrotu (oś y w dół)
			var sy := -dx * s + dy * c + cy - 0.5
			out.set_pixel(x, y, _sample(src, sx, sy))
	return out

static func _sample(img: Image, x: float, y: float) -> Color:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var c00 := _px(img, x0, y0)
	var c10 := _px(img, x0 + 1, y0)
	var c01 := _px(img, x0, y0 + 1)
	var c11 := _px(img, x0 + 1, y0 + 1)
	return c00.lerp(c10, fx).lerp(c01.lerp(c11, fx), fy)

static func _px(img: Image, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)
