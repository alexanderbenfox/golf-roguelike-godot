## PolylineUtils — static helpers for working with polyline spines.
##
## Used by HeightmapGenerator, HoleGenerator, and Camera for distance queries,
## parametric sampling, and length computation along multi-segment fairway spines.
class_name PolylineUtils
extends RefCounted


## Return the total arc length of a polyline.
static func total_length(spine: Array[Vector3]) -> float:
	var length: float = 0.0
	for i: int in range(spine.size() - 1):
		length += spine[i].distance_to(spine[i + 1])
	return length


## Sample a position at parametric t in [0, 1] along the polyline.
static func sample_position(spine: Array[Vector3], t: float) -> Vector3:
	if spine.size() < 2:
		return spine[0] if spine.size() > 0 else Vector3.ZERO
	t = clampf(t, 0.0, 1.0)
	var target_dist: float = t * total_length(spine)
	var accumulated: float = 0.0
	for i: int in range(spine.size() - 1):
		var seg_len: float = spine[i].distance_to(spine[i + 1])
		if accumulated + seg_len >= target_dist:
			var local_t: float = (target_dist - accumulated) / maxf(seg_len, 0.001)
			return spine[i].lerp(spine[i + 1], local_t)
		accumulated += seg_len
	return spine[spine.size() - 1]


## Sample the tangent direction at parametric t (XZ plane, normalized).
static func sample_direction(spine: Array[Vector3], t: float) -> Vector3:
	if spine.size() < 2:
		return Vector3.FORWARD
	t = clampf(t, 0.0, 1.0)
	var target_dist: float = t * total_length(spine)
	var accumulated: float = 0.0
	for i: int in range(spine.size() - 1):
		var seg_len: float = spine[i].distance_to(spine[i + 1])
		if accumulated + seg_len >= target_dist or i == spine.size() - 2:
			var d: Vector3 = spine[i + 1] - spine[i]
			return Vector3(d.x, 0.0, d.z).normalized()
		accumulated += seg_len
	var d: Vector3 = spine[spine.size() - 1] - spine[spine.size() - 2]
	return Vector3(d.x, 0.0, d.z).normalized()


## Return the perpendicular right vector for a given direction.
static func direction_to_right(dir: Vector3) -> Vector3:
	return Vector3(dir.z, 0.0, -dir.x)


## Return the minimum XZ distance from a point to the polyline.
static func min_distance_xz(point: Vector3, spine: Array[Vector3]) -> float:
	var flat := Vector3(point.x, 0.0, point.z)
	var best: float = INF
	for i: int in range(spine.size() - 1):
		var a := Vector3(spine[i].x, 0.0, spine[i].z)
		var b := Vector3(spine[i + 1].x, 0.0, spine[i + 1].z)
		var dist: float = _point_to_segment_xz(flat, a, b)
		best = minf(best, dist)
	return best


## Return [min_distance, global_parametric_t] for a point vs polyline (XZ).
## The returned t is in [0, 1] representing position along the full spine.
static func min_distance_and_t_xz(
	point: Vector3, spine: Array[Vector3],
) -> Array[float]:
	var flat := Vector3(point.x, 0.0, point.z)
	var best_dist: float = INF
	var best_seg: int = 0
	var best_local_t: float = 0.0

	for i: int in range(spine.size() - 1):
		var a := Vector3(spine[i].x, 0.0, spine[i].z)
		var b := Vector3(spine[i + 1].x, 0.0, spine[i + 1].z)
		var ab := b - a
		var ap := flat - a
		var ab_len_sq: float = ab.x * ab.x + ab.z * ab.z
		var local_t: float = 0.0
		if ab_len_sq > 0.001:
			local_t = clampf(
				(ap.x * ab.x + ap.z * ab.z) / ab_len_sq,
				0.0, 1.0,
			)
		var closest := Vector3(
			a.x + ab.x * local_t, 0.0, a.z + ab.z * local_t,
		)
		var dist: float = (flat - closest).length()
		if dist < best_dist:
			best_dist = dist
			best_seg = i
			best_local_t = local_t

	# Convert segment index + local t to global parametric t
	var seg_lengths: Array[float] = []
	var spine_length: float = 0.0
	for i: int in range(spine.size() - 1):
		var sl: float = Vector3(
			spine[i + 1].x - spine[i].x, 0.0,
			spine[i + 1].z - spine[i].z,
		).length()
		seg_lengths.append(sl)
		spine_length += sl

	if spine_length < 0.001:
		return [best_dist, 0.0]

	var accumulated: float = 0.0
	for i: int in range(best_seg):
		accumulated += seg_lengths[i]
	accumulated += seg_lengths[best_seg] * best_local_t
	var global_t: float = accumulated / spine_length

	return [best_dist, global_t]


## Return the XZ distance from a point to a line segment (clamped).
static func _point_to_segment_xz(
	point: Vector3, seg_a: Vector3, seg_b: Vector3,
) -> float:
	var ab := Vector3(
		seg_b.x - seg_a.x, 0.0, seg_b.z - seg_a.z,
	)
	var ap := Vector3(
		point.x - seg_a.x, 0.0, point.z - seg_a.z,
	)
	var ab_len_sq: float = ab.x * ab.x + ab.z * ab.z
	if ab_len_sq < 0.001:
		return ap.length()
	var t: float = clampf(
		(ap.x * ab.x + ap.z * ab.z) / ab_len_sq, 0.0, 1.0,
	)
	var closest := Vector3(
		seg_a.x + ab.x * t, 0.0, seg_a.z + ab.z * t,
	)
	return Vector3(
		point.x - closest.x, 0.0, point.z - closest.z,
	).length()
