class_name Barricade
extends Node3D
## A window barricade. `boards` (max Balance.barricade_boards) blocks zombies; a NavigationLink3D through the
## window is enabled only at 0 boards. Local +Z is the outside (zombie side). One zombie tears at a time (claim).

signal board_repaired(by: int)
signal boards_changed(boards: int)

const LINK_REACH := 1.0          # link endpoints sit this far in front of / behind the window (on the nav mesh edges)
const TEAR_REACH := 2.2          # a zombie this close (outside) may tear boards

var boards := 0
var max_boards := 0
var link: NavigationLink3D
var _claim := 0

func _init() -> void:
	max_boards = Content.balance.barricade_boards
	boards = max_boards
	add_to_group(&"barricades")
	link = NavigationLink3D.new()
	link.bidirectional = false
	link.start_position = Vector3(0, 0, LINK_REACH)
	link.end_position = Vector3(0, 0, -LINK_REACH)
	link.enabled = false
	add_child(link)

func outside_dir() -> Vector3:
	return global_transform.basis.z if is_inside_tree() else transform.basis.z

func is_outside(p: Vector3) -> bool:
	var origin := global_position if is_inside_tree() else position
	return (p - origin).dot(outside_dir()) > 0.0

func distance_to(p: Vector3) -> float:
	var origin := global_position if is_inside_tree() else position
	return origin.distance_to(p)

## Client mirror / host internal: set the board count (and the link) directly.
func set_boards(n: int) -> void:
	boards = clampi(n, 0, max_boards)
	link.enabled = boards == 0
	boards_changed.emit(boards)

## Host: a zombie removes a board. False when there is none left.
func tear_one() -> bool:
	if boards <= 0:
		return false
	set_boards(boards - 1)
	return true

## Host: player `by` nails a board back. False when already full.
func repair_one(by: int) -> bool:
	if boards >= max_boards:
		return false
	set_boards(boards + 1)
	board_repaired.emit(by)
	return true

## One tearer at a time; the claim holder keeps it until release().
func try_claim(zid: int) -> bool:
	if _claim == 0 or _claim == zid:
		_claim = zid
		return true
	return false

func release(zid: int) -> void:
	if _claim == zid:
		_claim = 0
