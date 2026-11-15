extends SceneTree
## Test GDExtension: natywny dekoder VHGT daje to samo co ścieżka GDScript/Python.
func _init() -> void:
	var fails := []
	if not ClassDB.class_exists("MWNative"):
		print("RESULT ", JSON.stringify({"failures": ["brak klasy MWNative (rozszerzenie nie zbudowane?)"]}))
		quit(1)
		return
	var n = ClassDB.instantiate("MWNative")
	# VHGT: offset 10, pierwsza kolumna +1 na wiersz, w wierszu +2 na kolumnę
	var b := PackedByteArray()
	b.resize(4 + 65 * 65 + 3)
	b.encode_float(0, 10.0)
	for y in 65:
		for x in 65:
			b.encode_s8(4 + y * 65 + x, 1 if x == 0 else 2)
	var h: PackedFloat32Array = n.decode_vhgt(b)
	# h[y][x] = (10 + (y+1) + 2x) * 8
	for y in [0, 10, 64]:
		for x in [0, 5, 64]:
			var exp: float = (10.0 + (y + 1) + 2.0 * x) * 8.0
			if absf(h[y * 65 + x] - exp) > 1e-3:
				fails.append("h[%d][%d]=%f, oczekiwano %f" % [y, x, h[y * 65 + x], exp])
	print("RESULT ", JSON.stringify({"version": n.version(), "failures": fails}))
	quit(0 if fails.is_empty() else 1)
