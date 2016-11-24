def do(gen):
	# Render a reference frame in 128 jobs of 1024 samples per pixel each.
	gen.queueAverage(
		scene = 'crytek_sponza',
		frame = 59,
		seed = 512,
		spp = 1024,
		frame_time = 1.0,
		shutter_time = 0.5,
		frame_count = 128
	)