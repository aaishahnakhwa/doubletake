extends CharacterBody2D

var move_input := Vector2.ZERO
var sprinting := false
var walk_speed := 155.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	collider.shape = shape
	add_child(collider)


func _physics_process(_delta: float) -> void:
	velocity = move_input.limit_length(1.0) * walk_speed * (1.38 if sprinting else 1.0)
	move_and_slide()
