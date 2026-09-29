extends SceneTree
## Join codes (gate stage F): encode / decode round trip, typo tolerance,
## garbage rejected, and a listen host shows its LAN code in the status.
##   godot --headless -s tools/join_code_test.gd

var _n := 0


func _process(_d: float) -> bool:
	_n += 1
	if _n < 3:
		return false
	var Net = root.get_node("Net")
	var bad: Array = []
	for c in [["192.168.1.23", 7777], ["10.0.0.5", 7790], ["255.255.255.255", 65535], ["1.2.3.4", 1], ["100.101.102.103", 7777]]:
		var code: String = Net.join_code(c[0], c[1])
		var back: Array = Net.parse_join_code(code)
		if back != c:
			bad.append("%s -> %s -> %s" % [str(c), code, str(back)])
		# Lower case, spaces, O for 0 / I for 1 still work.
		var sloppy := code.to_lower().replace("-", " ").replace("0", "o").replace("1", "i")
		if Net.parse_join_code(sloppy) != c:
			bad.append("sloppy %s" % sloppy)
	for g in ["", "hello", "192.168.1.1", "ZZZZZ-ZZZZZ", "12345-6789"]:
		if not Net.parse_join_code(g).is_empty():
			bad.append("accepted garbage '%s'" % g)
	if Net.join_code("not.an.ip", 7777) != "":
		bad.append("coded a bad ip")
	var sample: String = Net.join_code("192.168.1.23", 7777)
	var hosted: bool = Net.host_game(7000 + randi() % 500, 0)
	var st: String = Net.status
	var lan_ok: bool = Net.lan_ips().is_empty() or st.contains(Net.lan_code())
	if not hosted or not lan_ok:
		bad.append("host status '%s'" % st)
	Net.leave()
	print("JOINCODE-TEST %s %s | sample=%s status=%s" % ["ok" if bad.is_empty() else "FAIL", str(bad), sample, st.replace("\n", " / ")])
	quit()
	return true
