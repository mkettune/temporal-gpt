def do(gen, spps):
	for spp in spps:
		# GPT with adaptive sampling.
		gen.queueAdaptiveGPT(
			scene = 'crytek_sponza',
			seed = 0,
			spp = spp,
			frame_time = 1.0,
			shutter_time = 0.5,
			frame_count = 240
		)
		