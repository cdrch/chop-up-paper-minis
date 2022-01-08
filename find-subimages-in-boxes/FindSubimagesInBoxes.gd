extends Node2D


var FUZZY_MATCH_DIFF = 0.34 #0.1
var SKIPPABLE_PIXEL_COUNT = 8
# Declare member variables here. Examples:
# var a: int = 2
# var b: String = "text"
#var test_image = preload("res://test_images/page-07.png")
#var test_image = preload("res://test_images/testtiny.png")
var images = []
var image_directory = Directory.new()
var thread
var progress := Vector2(0,0)
var done = false
var image_counter = 1
var move_to_next_pixel = false
var list_of_rects = []

# Debug
var program_timer := 0.0
var pixels_discarded_by_h_line_check := 0
var pixels_discarded_by_v_line_check := 0
var outer_loops_discard := 0
var inner_loops_discard := 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	image_directory.open("res://trouble_pages")
	image_directory.list_dir_begin(true)
	thread = Thread.new()
	thread.start(self, "_thread_function")
	pass # Replace with function body.

func _exit_tree() -> void:
	thread.wait_to_finish()

func _thread_function():
	# Load images
	var next_image = image_directory.get_next()
	while next_image != "":
		if not next_image.ends_with("import"):
			images.append(load("res://trouble_pages/" + next_image))
			print(next_image)
		next_image = image_directory.get_next()
	# Call function
	for i in images:
		i.lock()
		_find_some_dang_boxes(i, 150, 16000, "user://test")
		list_of_rects = []
		i.unlock()
	print("Done")
	print(program_timer)
	print("Outer loop discards: " + str(outer_loops_discard))
	print("Inner loop discards: " + str(inner_loops_discard))
	print("V discards: " + str(pixels_discarded_by_v_line_check))
	print("H discards: " + str(pixels_discarded_by_h_line_check))
	get_tree().quit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	program_timer += delta
	pass


func _find_some_dang_boxes(image: Image, min_box_dimension: int, 
		max_box_dimension: int, path_for_subimages: String) -> void:
	var box_color := Color.black
	# Helper data
	var min_box := Vector2(min_box_dimension, min_box_dimension)
	var max_box := Vector2(max_box_dimension, max_box_dimension)
	var iteration_end := Vector2(image.get_width(), image.get_height()) - min_box # exclusive
	# Iterate over all pixels, y and x, ending at image size limits - min_box
	_iterate_over_all_pixels(image, box_color, min_box, max_box, path_for_subimages, Vector2(0,0), iteration_end)
	pass


# Note that end is exclusive
func _iterate_over_all_pixels(image: Image, box_color: Color, min_box: Vector2, 
		max_box: Vector2, path_for_subimages: String, start: Vector2, end: Vector2) -> void:
	for y in range(start.y, end.y):
#		print(y)
		for x in range(start.x, end.x):
#			print(Vector2(x,y))
			# Within each iteration:
			# If not box_color, continue
			if not _fuzzy_match_colors(image.get_pixel(x, y),  box_color):
				outer_loops_discard += 1
				continue
			# Else, iterate over all pixels, y and x, starting at +min_box and ending at +max_box or image size limits
			
			# Check for at least min_box of valid borders
			var valid_h_pixels = _valid_consecutive_pixels_horizontal(image, box_color, Vector2(x,y), min(max_box.x, image.get_width()))
#			print(valid_h_pixels)
			if valid_h_pixels < min_box.x:
				pixels_discarded_by_h_line_check += 1
				continue
			var valid_v_pixels = _valid_consecutive_pixels_vertical(image, box_color, Vector2(x,y), min(max_box.y, image.get_height()))
			if valid_v_pixels < min_box.y:
				pixels_discarded_by_v_line_check += 1				
				continue
			
			var new_end = Vector2(
					min(image.get_width(), min(x + max_box.x, x + valid_h_pixels)), 
					min(image.get_height(), min(y + max_box.y, y + valid_v_pixels))
			)
			# Do not look if too close to the edge
			# TODO - does this ^^^ need a check?
#			print(str(Vector2(x, y)) + " ? " + str(Vector2(x, y) + min_box))

			
			
			# Do not search through more than the discovered largest borders
#			var current_max_box = Vector2(min(max_box.x, valid_h_pixels), min(max_box.y, valid_v_pixels))
			
			_look_for_opposite_corners(image, box_color, path_for_subimages, Vector2(x, y), Vector2(x, y) + min_box, new_end)
	pass


func _look_for_opposite_corners(image: Image, box_color: Color, path_for_subimages: String, first_corner: Vector2, start: Vector2, end: Vector2) -> void:
	# Within each iteration:
#	print("looking for opposite corners...")
	for y in range(start.y, end.y):
		for x in range(start.x, end.x):
			# If not box_color, continue
#			print(image.get_pixel(x, y))
			if not _fuzzy_match_colors(image.get_pixel(x, y),  box_color):
				inner_loops_discard += 1
				continue
#			print("opposite corner found")
#			print("Here at " + str(Vector2(x, y)))
			# Else, we have two potential box corners: first_corner and second_corner
			var second_corner = Vector2(x, y)
			_check_if_corners_make_a_valid_rect(image, box_color, path_for_subimages, first_corner, second_corner)
			if move_to_next_pixel:
				move_to_next_pixel = false
				return
				
	
	pass

func _check_if_corners_make_a_valid_rect(image: Image, box_color: Color, path_for_subimages: String, first_corner: Vector2, second_corner: Vector2) -> void:
	# Get the four side values
	var left := min(first_corner.x, second_corner.x)
	var right := max(first_corner.x, second_corner.x)
	var top := min(first_corner.y, second_corner.y)
	var bottom := max(first_corner.y, second_corner.y)
	
	# Ensure this area is not already used
	var rect_to_check = Rect2(left, top, right - left, bottom - top)
	for rect in list_of_rects:
		if rect_to_check.intersects(rect, false):
			return
	
#	print(str(left) + "|" + str(right) + "|" + str(top) + "|" + str(bottom))
	# Check that each line is valid (image.get_pixel() == box_color) between the perpendicular limits
	# If any are false, break the check and continue onto the next iteration
	# Check left
#	for y in range(top, bottom+1):
#		if not _fuzzy_match_colors(image.get_pixel(left, y),  box_color):
#			return
	# Check right
	var skipped = 0
	for y in range(top, bottom+1):
		if not _fuzzy_match_colors(image.get_pixel(right, y),  box_color):
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				return
		else:
			skipped = 0
	# Check top
#	for x in range(left, right+1):
#		if not _fuzzy_match_colors(image.get_pixel(x, top),  box_color):
#			return
	# Check bottom
	skipped = 0
	for x in range(left, right+1):
		if not _fuzzy_match_colors(image.get_pixel(x, bottom),  box_color):
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				return
		else:
			skipped = 0
	# If none are false, we have a valid box outline
	# Check the inside for valid content
	print("box border valid")
	_check_that_box_content_is_valid(image, path_for_subimages, left, right, top, bottom)
	pass


func _check_that_box_content_is_valid(image: Image,	path_for_subimages: String, left: int, right: int, top: int, bottom: int) -> void:
	# Iterate over all pixels inside the box, y and x, starting 
	# at (left+1,top+1) and ending at (right-1, bottom-1), inclusive
	for y in range(top+1, bottom):
		for x in range(left+1, right):
			# If any are not transparent, this is a valid subimage; else, break the check and continue onto the next iteration
			if image.get_pixel(x, y) == Color.transparent:
				return
	# Image is valid!
	list_of_rects.append(Rect2(left+1, top+1, right-left-2, bottom-top-2))
	move_to_next_pixel = true
	# Save the subimage, including the bordering box
	_save_subimage(image, path_for_subimages, left, right, top, bottom)
		
	pass


func _save_subimage(image: Image, path_for_subimages: String, left: int, right: int, top: int, bottom: int) -> void:
	# Save the subimage, including the bordering box
	# Get the area
	var rect := Rect2(left, top, 1, 1)
	rect = rect.expand(Vector2(right, bottom))
	var subimage := image.get_rect(rect)
	# Save the image
	var e = subimage.save_png(path_for_subimages + "/" + str(image_counter) + ".png")
	print("Error: " + str(e))
	print("Saved image.")
	print(path_for_subimages + "/" + str(image_counter) + ".png")
	
	# Delete the subimage from the working image, excluding the bordering box
#	_delete_subimage_from_working_image(image, left, right, top, bottom)
	# Debug visualization
#	image.save_png(path_for_subimages + "/" + str(image_counter) + "b.png")
#	image.save_png(path_for_subimages + "/" + str(image_counter) + "b.png")
	image_counter += 1
	
	pass


func _delete_subimage_from_working_image(image: Image, left: int, right: int, top: int, bottom: int) -> void:	
	# Delete the subimage from the working image, including the bordering box only on the left and right
	for y in range(top+1, bottom):
		for x in range(left+1, right):
			image.set_pixel(x, y, Color.transparent)
	# Proceed to the next iteration	
	pass


func _fuzzy_match_colors(color1: Color, color2: Color) -> bool:
	return color1.is_equal_approx(color2) || (_fuzzy_match(color1.r, color2.r) && _fuzzy_match(color1.g, color2.g) && _fuzzy_match(color1.b, color2.b))


func _fuzzy_match(a: float, b: float) -> bool:
	if abs(a-b) <= FUZZY_MATCH_DIFF:
		return true
	return false


func _valid_consecutive_pixels_horizontal(image: Image, color: Color, start: Vector2, max_size: int) -> int:
	# Start at corner
	# Go to the right until invalid pixel found, counting as we go
	var count = 0
	var skipped = 0
	for x in range(start.x, start.x + max_size):
		for rect in list_of_rects:
			if rect.has_point(Vector2(x, start.y)):
				return count
		if not _fuzzy_match_colors(image.get_pixel(x, start.y),  color):
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				return count - skipped
		else:
			skipped = 0
		count += 1	
	return count # should be equal to max_size


func _valid_consecutive_pixels_vertical(image: Image, color: Color, start: Vector2, max_size: int) -> int:
	# Start at corner
	# Go to the right until invalid pixel found, counting as we go
	var count = 0
	var skipped = 0
	for y in range(start.y, start.y + max_size):
		for rect in list_of_rects:
			if rect.has_point(Vector2(start.x, y)):
				return count
		if not _fuzzy_match_colors(image.get_pixel(start.x, y),  color):
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				return count - skipped
		else:
			skipped = 0
		count += 1	
	return count # should be equal to max_size


