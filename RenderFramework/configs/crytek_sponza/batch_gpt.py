def do(gen, spps):
	for spp in spps:
		# GPT as it stands in the GPT paper.
		gen.queueGPT(
			scene = 'crytek_sponza',
			seed = 0,
			spp = spp,
			frame_time = 1.0,
			shutter_time = 0.5,
			frame_count = 240
		)
		