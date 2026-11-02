class_name LanBeacon
extends Node
## LAN discovery over UDP. Host: broadcasts a small JSON beacon once a second. Listen: emits found().
const MAGIC := "site62"
const EXPIRE := 4.0
signal found(ip: String, port: int, name: String, players: int)

var mode := ""
var port := 7800
var info_cb := Callable()   # host: returns {port, name, players}
var _udp := PacketPeerUDP.new()
var _t := 0.0
var _seen := {}             # "ip:port" -> last seen seconds

func start_host(beacon_port: int, cb: Callable) -> void:
	mode = "host"
	port = beacon_port
	info_cb = cb
	_udp.set_broadcast_enabled(true)
	_t = 0.0

func start_listen(beacon_port: int) -> bool:
	mode = "listen"
	port = beacon_port
	var err := _udp.bind(port, "*")
	if err != OK:
		push_warning("LAN beacon listen failed: %d" % err)
		return false
	return true

func _exit_tree() -> void:
	_udp.close()

func _process(dt: float) -> void:
	if mode == "host":
		_t -= dt
		if _t <= 0.0:
			_t = 1.0
			var d: Dictionary = info_cb.call()
			d["g"] = MAGIC
			var pkt := JSON.stringify(d).to_utf8_buffer()
			for addr in ["255.255.255.255", "127.0.0.1"]:
				_udp.set_dest_address(addr, port)
				_udp.put_packet(pkt)
	elif mode == "listen":
		var now := Time.get_ticks_msec() / 1000.0
		while _udp.get_available_packet_count() > 0:
			var ip := _udp.get_packet_ip()
			var d = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
			if typeof(d) != TYPE_DICTIONARY or d.get("g", "") != MAGIC:
				continue
			var p := int(d.get("port", 0))
			var key := "%s:%d" % [ip, p]
			if not _seen.has(key) or now - _seen[key] > EXPIRE:
				found.emit(ip, p, str(d.get("name", "?")), int(d.get("players", 0)))
			_seen[key] = now
