class_name TaskCatalog
extends RefCounted

const TASKS := [
	{
		"id": "firewood",
		"icon": "res://assets/task_icons/firewood.png",
		"name": "Collect firewood",
		"instruction": "Gather every dry log before leaving the trail.",
		"mode": "targets",
		"drop_label": "DRAG FIREWOOD TO THE CAMP PILE",
		"items": ["LOG", "TWIGS", "BRANCH", "KINDLING", "BARK"],
		"item_sprites": [
			"res://assets/task_draggables/firewood/log.png",
			"res://assets/task_draggables/firewood/twigs.png",
			"res://assets/task_draggables/firewood/branch.png",
			"res://assets/task_draggables/firewood/kindling.png",
			"res://assets/task_draggables/firewood/bark.png"
		]
	},
	{
		"id": "generator",
		"icon": "res://assets/task_icons/generator.png",
		"name": "Fix the generator",
		"instruction": "Reconnect the numbered breakers in order.",
		"mode": "sequence",
		"items": ["1  FUSE", "2  BELT", "3  FUEL", "4  START"],
		"item_sprites": [
			"res://assets/task_draggables/generator/fuse.png",
			"res://assets/task_draggables/generator/belt.png",
			"res://assets/task_draggables/generator/fuel.png",
			"res://assets/task_draggables/generator/start.png"
		],
		"target_states": [
			"res://assets/task_draggables/generator/states/broken.png",
			"res://assets/task_draggables/generator/states/fuse.png",
			"res://assets/task_draggables/generator/states/belt.png",
			"res://assets/task_draggables/generator/states/fuel.png",
			"res://assets/task_draggables/generator/states/running.png"
		]
	},
	{
		"id": "dinner",
		"icon": "res://assets/task_icons/dinner.png",
		"name": "Prepare dinner",
		"instruction": "Add the ingredients in the recipe order.",
		"mode": "sequence",
		"items": ["1  WATER", "2  VEGETABLES", "3  SPICES", "4  STIR"],
		"item_sprites": [
			"res://assets/task_draggables/dinner/water.png",
			"res://assets/task_draggables/dinner/vegetables.png",
			"res://assets/task_draggables/dinner/spices.png",
			"res://assets/task_draggables/dinner/stir.png"
		],
		"target_states": [
			"res://assets/task_draggables/dinner/states/empty.png",
			"res://assets/task_draggables/dinner/states/water.png",
			"res://assets/task_draggables/dinner/states/vegetables.png",
			"res://assets/task_draggables/dinner/states/spices.png",
			"res://assets/task_draggables/dinner/states/finished.png"
		]
	},
	{
		"id": "cabins",
		"icon": "res://assets/task_icons/cabins.png",
		"name": "Tidy the cabins",
		"instruction": "Put away everything left around the bunks.",
		"mode": "matching",
		"items": ["BLANKET", "BOOTS", "PILLOW", "BAG", "BOOK"],
		"destinations": ["FOOTLOCKER", "BOOT RACK", "BED", "WALL HOOK", "BOOKSHELF"],
		"item_sprites": [
			"res://assets/task_draggables/cabins/blanket.png",
			"res://assets/task_draggables/cabins/boots.png",
			"res://assets/task_draggables/cabins/pillow.png",
			"res://assets/task_draggables/cabins/bag.png",
			"res://assets/task_draggables/cabins/book.png"
		],
		"destination_sprites": [
			"res://assets/task_draggables/cabins/destinations/footlocker.png",
			"res://assets/task_draggables/cabins/destinations/boot_rack.png",
			"res://assets/task_draggables/cabins/destinations/bed.png",
			"res://assets/task_draggables/cabins/destinations/wall_hook.png",
			"res://assets/task_draggables/cabins/destinations/bookshelf.png"
		],
		"destination_filled_sprites": [
			"res://assets/task_draggables/cabins/filled/footlocker.png",
			"res://assets/task_draggables/cabins/filled/boot_rack.png",
			"res://assets/task_draggables/cabins/filled/bed.png",
			"res://assets/task_draggables/cabins/filled/wall_hook.png",
			"res://assets/task_draggables/cabins/filled/bookshelf.png"
		]
	},
	{
		"id": "tools",
		"icon": "res://assets/task_icons/tools.png",
		"name": "Sort workshop tools",
		"instruction": "Return each tool to its marked rack slot.",
		"mode": "sequence",
		"items": ["1  HAMMER", "2  SAW", "3  WRENCH", "4  PLIERS", "5  TAPE"],
		"item_sprites": [
			"res://assets/task_draggables/tools/hammer.png",
			"res://assets/task_draggables/tools/saw.png",
			"res://assets/task_draggables/tools/wrench.png",
			"res://assets/task_draggables/tools/pliers.png",
			"res://assets/task_draggables/tools/tape.png"
		],
		"target_states": [
			"res://assets/task_draggables/tools/states/empty.png",
			"res://assets/task_draggables/tools/states/hammer.png",
			"res://assets/task_draggables/tools/states/saw.png",
			"res://assets/task_draggables/tools/states/wrench.png",
			"res://assets/task_draggables/tools/states/pliers.png",
			"res://assets/task_draggables/tools/states/complete.png"
		]
	},
	{
		"id": "lanterns",
		"icon": "res://assets/task_icons/lanterns.png",
		"name": "Refill lanterns",
		"instruction": "Fuel the lantern, build pressure, then light it with a match.",
		"mode": "rhythm",
		"items": ["LANTERN", "HAND PUMP", "FUEL CAN", "MATCHES"],
		"item_sprites": [
			"res://assets/task_draggables/lanterns/lantern.png",
			"res://assets/task_draggables/lanterns/pump.png",
			"res://assets/task_draggables/lanterns/fuel.png",
			"res://assets/task_draggables/lanterns/matches.png"
		],
		"task_assets": [
			"res://assets/task_draggables/lanterns/match_unlit.png",
			"res://assets/task_draggables/lanterns/match_lit.png"
		]
	},
	{
		"id": "dock",
		"icon": "res://assets/task_icons/dock.png",
		"name": "Repair dock boards",
		"instruction": "Drive all three nails flush into the damaged dock plank.",
		"mode": "hammer",
		"items": ["LEFT NAIL", "CENTER NAIL", "RIGHT NAIL"],
		"item_sprites": [
			"res://assets/task_draggables/dock/nail.png",
			"res://assets/task_draggables/dock/nail.png",
			"res://assets/task_draggables/dock/nail.png"
		],
		"task_assets": [
			"res://assets/task_draggables/dock/hammer.png",
			"res://assets/task_draggables/dock/cracked_plank.png",
			"res://assets/task_draggables/dock/repaired_plank.png"
		]
	},
	{
		"id": "lake",
		"icon": "res://assets/task_icons/lake.png",
		"name": "Clear lake debris",
		"instruction": "Remove all debris caught beside the dock.",
		"mode": "targets",
		"drop_label": "DRAG DEBRIS INTO THE CLEANUP NET",
		"items": ["BOTTLE", "CAN", "ROPE", "BAG"],
		"item_sprites": [
			"res://assets/task_draggables/lake/bottle.png",
			"res://assets/task_draggables/lake/can.png",
			"res://assets/task_draggables/lake/rope.png",
			"res://assets/task_draggables/lake/bag.png"
		],
		"task_assets": [
			"res://assets/task_draggables/lake/net.png"
		]
	},
	{
		"id": "radio",
		"icon": "res://assets/task_icons/radio.png",
		"name": "Tune the camp radio",
		"instruction": "Tune into the green frequency and hold the signal steady.",
		"mode": "dial",
		"items": ["RADIO", "TUNING KNOB", "NEEDLE", "SIGNAL"],
		"item_sprites": [
			"res://assets/task_draggables/radio/radio.png",
			"res://assets/task_draggables/radio/knob.png",
			"res://assets/task_draggables/radio/needle.png",
			"res://assets/task_draggables/radio/signal.png"
		]
	},
	{
		"id": "supplies",
		"icon": "res://assets/task_icons/supplies.png",
		"name": "Find missing supplies",
		"instruction": "Find the three requested supplies hidden in the storeroom.",
		"mode": "find",
		"items": ["FIRST AID", "BATTERIES", "MATCHES", "CANTEEN", "COMPASS", "SOAP"],
		"item_sprites": [
			"res://assets/task_draggables/supplies/first_aid.png",
			"res://assets/task_draggables/supplies/batteries.png",
			"res://assets/task_draggables/supplies/matches.png",
			"res://assets/task_draggables/supplies/canteen.png",
			"res://assets/task_draggables/supplies/compass.png",
			"res://assets/task_draggables/supplies/soap.png"
		]
	}
]

const SABOTAGE_TASKS := {
	"generator": {
		"id": "generator",
		"icon": "res://assets/phase4/sabotage/generator.png",
		"name": "Overload the generator",
		"instruction": "Disable the safety systems in order without alerting the camp.",
		"mode": "sabotage",
		"sabotage_panel": "res://assets/phase4/sabotage_tasks/generator_overload.png",
		"sabotage_states": "res://assets/phase4/sabotage_tasks/generator_states.png",
		"sabotage_steps": ["CUT CABLE", "FLIP BREAKER", "PULL FUSE"]
	},
	"radio": {
		"id": "radio",
		"icon": "res://assets/phase4/sabotage/radio.png",
		"name": "Jam the radio",
		"instruction": "Push the transmitter into static and lock the jammed signal.",
		"mode": "sabotage",
		"sabotage_panel": "res://assets/phase4/sabotage_tasks/radio_jammer.png",
		"sabotage_states": "res://assets/phase4/sabotage_tasks/radio_states.png",
		"sabotage_steps": ["TURN JAMMER", "SHIFT SIGNAL", "LOCK STATIC"]
	},
	"supplies": {
		"id": "supplies",
		"icon": "res://assets/phase4/sabotage/supplies.png",
		"name": "Hide the supplies",
		"instruction": "Conceal the essentials and lock the camp locker.",
		"mode": "sabotage",
		"sabotage_panel": "res://assets/phase4/sabotage_tasks/supply_lock.png",
		"sabotage_states": "res://assets/phase4/sabotage_tasks/supplies_states.png",
		"sabotage_steps": ["HIDE MEDKIT", "HIDE BATTERIES", "LOCK CABINET"]
	},
	"lanterns": {
		"id": "lanterns",
		"icon": "res://assets/phase4/sabotage/lanterns.png",
		"name": "Douse the lantern",
		"instruction": "Starve the lantern, smother its flame, and remove the fuel.",
		"mode": "sabotage",
		"sabotage_panel": "res://assets/phase4/sabotage_tasks/lantern_douse.png",
		"sabotage_states": "res://assets/phase4/sabotage_tasks/lantern_states.png",
		"sabotage_steps": ["CLOSE VALVE", "DROP SNUFFER", "REMOVE FUEL"]
	}
}


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for task: Dictionary in TASKS:
		result.append(str(task["id"]))
	return result


static func get_task(task_id: String) -> Dictionary:
	for task: Dictionary in TASKS:
		if task["id"] == task_id:
			return task.duplicate(true)
	return {}


static func get_sabotage_task(task_id: String) -> Dictionary:
	if SABOTAGE_TASKS.has(task_id):
		return SABOTAGE_TASKS[task_id].duplicate(true)
	return {}


static func make_assignment(task_id: String) -> Dictionary:
	var task := get_task(task_id)
	if task.is_empty():
		return {}
	return {
		"id": task_id,
		"name": task["name"],
		"icon": task["icon"],
		"completed": false
	}
