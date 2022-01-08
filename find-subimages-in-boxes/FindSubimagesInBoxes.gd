extends Node2D


var FUZZY_MATCH_DIFF = 0.34 #0.1
var SKIPPABLE_PIXEL_COUNT = 8

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


var ready_total_time := 0.0
func _ready() -> void:
	var start = OS.get_ticks_usec()
	image_directory.open("res://trouble_pages")
	image_directory.list_dir_begin(true)
	thread = Thread.new()
	thread.start(self, "_thread_function")
	var end = OS.get_ticks_usec()
	ready_total_time += (end-start)/1000000.0


func _exit_tree() -> void:
	thread.wait_to_finish()


var thread_function_total_time := 0.0
func _thread_function():
	var start = OS.get_ticks_usec()
	var end
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
		print("Works here")
		thread_function_total_time += (end-start)/1000000.0
		print("Does not work here")
		_find_some_dang_boxes(i, 150, 16000, "user://test")
		start = OS.get_ticks_usec()
		list_of_rects = []
		i.unlock()
	end = OS.get_ticks_usec()
	thread_function_total_time += (end-start)/1000000.0
	print("Done")
	print("Program time: " + str(program_timer))
	
	print("Function times (seconds)")
	print("ready: " + str(ready_total_time))
	print("thread_function: " + str(thread_function_total_time))
	print("find_some_dang_boxes: " + str(find_some_dang_boxes_total_time))
	print("iterate_over_all_pixels: " + str(iterate_over_all_pixels_total_time))
	print("look_for_opposite_corners: " + str(look_for_opposite_corners_total_time))
	print("check_if_corners_make_a_valid_rect: " + str(check_if_corners_make_a_valid_rect_total_time))
	print("check_that_box_content_is_valid: " + str(check_that_box_content_is_valid_total_time))
	print("save_subimage: " + str(save_subimage_total_time))
	print("fuzzy_match(_colors): " + str(fuzzy_match_colors_total_time))
	print("valid_consecutive_pixels_horizontal: " + str(valid_consecutive_pixels_horizontal_total_time))
	print("valid_consecutive_pixels_vertical: " + str(valid_consecutive_pixels_vertical_total_time))
	
	print("Outer loop discards: " + str(outer_loops_discard))
	print("Inner loop discards: " + str(inner_loops_discard))
	print("V discards: " + str(pixels_discarded_by_v_line_check))
	print("H discards: " + str(pixels_discarded_by_h_line_check))
	get_tree().quit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	program_timer += delta
	pass


var find_some_dang_boxes_total_time := 0.0
func _find_some_dang_boxes(image: Image, min_box_dimension: int, 
		max_box_dimension: int, path_for_subimages: String) -> void:
	var start = OS.get_ticks_usec()
	var end
	var box_color := Color.black
	# Helper data
	var min_box := Vector2(min_box_dimension, min_box_dimension)
	var max_box := Vector2(max_box_dimension, max_box_dimension)
	var iteration_end := Vector2(image.get_width(), image.get_height()) - min_box # exclusive
	end = OS.get_ticks_usec()
	thread_function_total_time += (end-start)/1000000.0
	# Iterate over all pixels, y and x, ending at image size limits - min_box
	_iterate_over_all_pixels(image, box_color, min_box, max_box, path_for_subimages, Vector2(0,0), iteration_end)


var iterate_over_all_pixels_total_time := 0.0
# Note that end is exclusive
func _iterate_over_all_pixels(image: Image, box_color: Color, min_box: Vector2, 
		max_box: Vector2, path_for_subimages: String, start: Vector2, end: Vector2) -> void:
	var start2 = OS.get_ticks_usec()
	var end2
	for y in range(start.y, end.y):
		for x in range(start.x, end.x):
			# Within each iteration:
			# If not box_color, continue
			end2 = OS.get_ticks_usec()
			thread_function_total_time += (end2-start2)/1000000.0
			if not _fuzzy_match_colors(image.get_pixel(x, y),  box_color):
				outer_loops_discard += 1
				start2 = OS.get_ticks_usec()
				continue
			start2 = OS.get_ticks_usec()
			# Else, iterate over all pixels, y and x, starting at +min_box and ending at +max_box or image size limits
			
			# Check for at least min_box of valid borders
			end2 = OS.get_ticks_usec()
			thread_function_total_time += (end2-start2)/1000000.0
			var valid_h_pixels = _valid_consecutive_pixels_horizontal(image, box_color, Vector2(x,y), min(max_box.x, image.get_width()))
			start2 = OS.get_ticks_usec()
#			print(valid_h_pixels)
			if valid_h_pixels < min_box.x:
				pixels_discarded_by_h_line_check += 1
				continue
			end2 = OS.get_ticks_usec()
			thread_function_total_time += (end2-start2)/1000000.0
			var valid_v_pixels = _valid_consecutive_pixels_vertical(image, box_color, Vector2(x,y), min(max_box.y, image.get_height()))
			start2 = OS.get_ticks_usec()
			if valid_v_pixels < min_box.y:
				pixels_discarded_by_v_line_check += 1				
				continue
			
			var new_end = Vector2(
					min(image.get_width(), min(x + max_box.x, x + valid_h_pixels)), 
					min(image.get_height(), min(y + max_box.y, y + valid_v_pixels))
			)
			# Do not look if too close to the edge
			# TODO - does this ^^^ need a check?
			# Do not search through more than the discovered largest borders
#			var current_max_box = Vector2(min(max_box.x, valid_h_pixels), min(max_box.y, valid_v_pixels))
			
			end2 = OS.get_ticks_usec()
			thread_function_total_time += (end2-start2)/1000000.0
			_look_for_opposite_corners(image, box_color, path_for_subimages, Vector2(x, y), Vector2(x, y) + min_box, new_end)


var look_for_opposite_corners_total_time := 0.0
func _look_for_opposite_corners(image: Image, box_color: Color, path_for_subimages: String, first_corner: Vector2, start: Vector2, end: Vector2) -> void:
	var start3 = OS.get_ticks_usec()
	var end3
	# Within each iteration:
	for y in range(start.y, end.y):
		for x in range(start.x, end.x):
			# If not box_color, continue
			end3 = OS.get_ticks_usec()
			look_for_opposite_corners_total_time += (end3-start3)/1000000.0
			if not _fuzzy_match_colors(image.get_pixel(x, y),  box_color):
				start3 = OS.get_ticks_usec()
				inner_loops_discard += 1
				continue
			start3 = OS.get_ticks_usec()
			# Else, we have two potential box corners: first_corner and second_corner
			var second_corner = Vector2(x, y)
			end3 = OS.get_ticks_usec()
			look_for_opposite_corners_total_time += (end3-start3)/1000000.0
			_check_if_corners_make_a_valid_rect(image, box_color, path_for_subimages, first_corner, second_corner)
			start3 = OS.get_ticks_usec()
			if move_to_next_pixel:
				move_to_next_pixel = false
				return
	end3 = OS.get_ticks_usec()
	look_for_opposite_corners_total_time += (end3-start3)/1000000.0


var check_if_corners_make_a_valid_rect_total_time := 0.0
func _check_if_corners_make_a_valid_rect(image: Image, box_color: Color, path_for_subimages: String, first_corner: Vector2, second_corner: Vector2) -> void:
	var start4 = OS.get_ticks_usec()
	var end4
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
	var skipped = 0
	for y in range(top, bottom+1):
		end4 = OS.get_ticks_usec()
		check_if_corners_make_a_valid_rect_total_time += (end4-start4)/1000000.0
		if not _fuzzy_match_colors(image.get_pixel(right, y),  box_color):
			start4 = OS.get_ticks_usec()
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				return
		else:
			start4 = OS.get_ticks_usec()
			skipped = 0
	skipped = 0
	for x in range(left, right+1):
		end4 = OS.get_ticks_usec()
		check_if_corners_make_a_valid_rect_total_time += (end4-start4)/1000000.0
		if not _fuzzy_match_colors(image.get_pixel(x, bottom),  box_color):
			start4 = OS.get_ticks_usec()
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				return
		else:
			start4 = OS.get_ticks_usec()
			skipped = 0
	# If none are false, we have a valid box outline
	# Check the inside for valid content
#	print("box border valid")
	end4 = OS.get_ticks_usec()
	check_if_corners_make_a_valid_rect_total_time += (end4-start4)/1000000.0
	_check_that_box_content_is_valid(image, path_for_subimages, left, right, top, bottom)


var check_that_box_content_is_valid_total_time := 0.0
func _check_that_box_content_is_valid(image: Image,	path_for_subimages: String, left: int, right: int, top: int, bottom: int) -> void:
	var start5 = OS.get_ticks_usec()
	var end5
	# Iterate over all pixels inside the box, y and x, starting 
	# at (left+1,top+1) and ending at (right-1, bottom-1), inclusive
	for y in range(top+1, bottom):
		for x in range(left+1, right):
			# If any are not transparent, this is a valid subimage; else, break the check and continue onto the next iteration
			if image.get_pixel(x, y) == Color.transparent:
				end5 = OS.get_ticks_usec()
				check_that_box_content_is_valid_total_time += (end5-start5)/1000000.0
				return
	# Image is valid!
	list_of_rects.append(Rect2(left+1, top+1, right-left-2, bottom-top-2))
	move_to_next_pixel = true
	end5 = OS.get_ticks_usec()
	check_that_box_content_is_valid_total_time += (end5-start5)/1000000.0
	# Save the subimage, including the bordering box
	_save_subimage(image, path_for_subimages, left, right, top, bottom)


var save_subimage_total_time := 0.0
func _save_subimage(image: Image, path_for_subimages: String, left: int, right: int, top: int, bottom: int) -> void:
	var start6 = OS.get_ticks_usec()
	var end6
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
	end6 = OS.get_ticks_usec()
	save_subimage_total_time += (end6-start6)/1000000.0


#func _delete_subimage_from_working_image(image: Image, left: int, right: int, top: int, bottom: int) -> void:	
#	# Delete the subimage from the working image, including the bordering box only on the left and right
#	for y in range(top+1, bottom):
#		for x in range(left+1, right):
#			image.set_pixel(x, y, Color.transparent)


var fuzzy_match_colors_total_time := 0.0
func _fuzzy_match_colors(color1: Color, color2: Color) -> bool:
	var start7 = OS.get_ticks_usec()
	var result = color1.is_equal_approx(color2) || (_fuzzy_match(color1.r, color2.r) && _fuzzy_match(color1.g, color2.g) && _fuzzy_match(color1.b, color2.b))
	var end7 = OS.get_ticks_usec()
	fuzzy_match_colors_total_time += (end7-start7)/1000000.0
	return result

func _fuzzy_match(a: float, b: float) -> bool:
	if abs(a-b) <= FUZZY_MATCH_DIFF:
		return true
	return false


var valid_consecutive_pixels_horizontal_total_time := 0.0
func _valid_consecutive_pixels_horizontal(image: Image, color: Color, start: Vector2, max_size: int) -> int:
	var start8 = OS.get_ticks_usec()
	var end8
	# Start at corner
	# Go to the right until invalid pixel found, counting as we go
	var count = 0
	var skipped = 0
	for x in range(start.x, start.x + max_size):
		for rect in list_of_rects:
			if rect.has_point(Vector2(x, start.y)):
				end8 = OS.get_ticks_usec()
				valid_consecutive_pixels_horizontal_total_time += (end8-start8)/1000000.0
				return count
		valid_consecutive_pixels_horizontal_total_time += (end8-start8)/1000000.0
		if not _fuzzy_match_colors(image.get_pixel(x, start.y),  color):
			start8 = OS.get_ticks_usec()
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				end8 = OS.get_ticks_usec()
				valid_consecutive_pixels_horizontal_total_time += (end8-start8)/1000000.0
				return count - skipped
		else:
			start8 = OS.get_ticks_usec()
			skipped = 0
		count += 1
	end8 = OS.get_ticks_usec()
	valid_consecutive_pixels_horizontal_total_time += (end8-start8)/1000000.0
	return count # should be equal to max_size


var valid_consecutive_pixels_vertical_total_time := 0.0
func _valid_consecutive_pixels_vertical(image: Image, color: Color, start: Vector2, max_size: int) -> int:
	var start9 = OS.get_ticks_usec()
	var end9
	# Start at corner
	# Go to the right until invalid pixel found, counting as we go
	var count = 0
	var skipped = 0
	for y in range(start.y, start.y + max_size):
		for rect in list_of_rects:
			if rect.has_point(Vector2(start.x, y)):
				end9 = OS.get_ticks_usec()
				valid_consecutive_pixels_vertical_total_time += (end9-start9)/1000000.0
				return count
		end9 = OS.get_ticks_usec()
		valid_consecutive_pixels_vertical_total_time += (end9-start9)/1000000.0
		if not _fuzzy_match_colors(image.get_pixel(start.x, y),  color):
			start9 = OS.get_ticks_usec()
			skipped += 1
			if skipped > SKIPPABLE_PIXEL_COUNT:
				end9 = OS.get_ticks_usec()
				valid_consecutive_pixels_vertical_total_time += (end9-start9)/1000000.0
				return count - skipped
		else:
			start9 = OS.get_ticks_usec()
			skipped = 0
		count += 1
	end9 = OS.get_ticks_usec()
	valid_consecutive_pixels_vertical_total_time += (end9-start9)/1000000.0
	return count # should be equal to max_size

