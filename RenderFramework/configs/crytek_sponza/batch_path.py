def do(gen, spps):
	# Note: multiplying by 2.5 tries to make the renders approximately equal-time with T-GPT and GPT.
	
	for spp in spps:
		# Standard path tracing.
		gen.queuePath(
			scene = 'crytek_sponza',
			seed = 0,
			spp = int(2.5 * spp),
			frame_time = 1.0,
			shutter_time = 0.5,
			frame_count = 240
		)
		