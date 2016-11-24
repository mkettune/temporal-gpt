import generator
import crytek_sponza.batch_path
import crytek_sponza.batch_gpt
import crytek_sponza.batch_tgpt
import crytek_sponza.batch_reference_frame
import crytek_sponza.batch_adaptive_gpt

gen = generator.Generator('../cluster')

SPPS = (32, 256)

# Run batches.
crytek_sponza.batch_path.do(gen, SPPS)
crytek_sponza.batch_gpt.do(gen, SPPS)
crytek_sponza.batch_tgpt.do(gen, SPPS)
crytek_sponza.batch_adaptive_gpt.do(gen, SPPS)
crytek_sponza.batch_reference_frame.do(gen)


gen.close()
