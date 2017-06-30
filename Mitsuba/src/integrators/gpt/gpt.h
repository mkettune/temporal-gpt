/*
    This file is part of Mitsuba, a physically based rendering system.

    Copyright (c) 2007-2014 by Wenzel Jakob and others.

    Mitsuba is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License Version 3
    as published by the Free Software Foundation.

    Mitsuba is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#if !defined(__GPT_H)
#define __GPT_H

#include <mitsuba/mitsuba.h>
#include "gpt_wr.h"


#include "motion_map.h"
#include "sampling_map.h"


MTS_NAMESPACE_BEGIN


/* ==================================================================== */
/*                         Configuration storage                        */
/* ==================================================================== */


/// Configuration for the gradient path tracer.
struct GradientPathTracerConfig {
    int m_maxDepth;
	int m_minDepth;
    int m_rrDepth;
	bool m_strictNormals;
	
	Float m_shiftThreshold;		// threshold for G-PT diffuse / specular classification.
	bool m_reconstructL1;       // whether to reconstruct in L1
	bool m_reconstructL2;       // whether to reconstruct in L2
	Float m_reconstructAlpha;   // alpha to use for the reconstruction

	int m_seed;					// seed for sampler, only important if we use the deterministic sampler.
	Point2i m_seedShift;		// shift of seeds, used for computing 2nd order derivatives.

	bool m_useMotionVectors;	// do we use motion vectors to compute the time offsets?

	bool m_isBase;				// pass identifier used to determine if sampling map and motion vector map should be generated if required by useAdaptive and useMotionVectors 
	bool m_isTimeOffset;		// pass identifier to determine whether or not we are currently rendering time offsets (used for motion vector based time-shifts)

	bool m_useAdaptive;			// do we use adaptive sampling?
	int  m_sampling_iter;		// number of sampling iterations in case useAdaptive=true.

	bool m_disableGradients;	// whether to disable estimating the spatial gradients. Used e.g. for rendering standard PT images with GPT's adaptive sampling code.

	inline GradientPathTracerConfig() { }

	inline GradientPathTracerConfig(Stream *stream) {
		m_maxDepth = stream->readInt();
		m_minDepth = stream->readInt();
		m_rrDepth = stream->readInt();
		m_strictNormals = stream->readBool();

		m_shiftThreshold = stream->readFloat();
		m_reconstructL1 = stream->readBool();
		m_reconstructL2 = stream->readBool();
		m_reconstructAlpha = stream->readFloat();

		m_seed = stream->readInt();
		m_seedShift = Point2i(stream);

		m_useMotionVectors = stream->readBool();

		m_isBase = stream->readBool();
		m_isTimeOffset = stream->readBool();

		m_useAdaptive = stream->readBool();
		m_sampling_iter = stream->readInt();

		m_disableGradients = stream->readBool();
	}

	inline void serialize(Stream *stream) const {
		stream->writeInt(m_maxDepth);
		stream->writeInt(m_minDepth);
		stream->writeInt(m_rrDepth);
		stream->writeBool(m_strictNormals);

		stream->writeFloat(m_shiftThreshold);
		stream->writeBool(m_reconstructL1);
		stream->writeBool(m_reconstructL2);
		stream->writeFloat(m_reconstructAlpha);

		stream->writeInt(m_seed);
		m_seedShift.serialize(stream);

		stream->writeBool(m_useMotionVectors);

		stream->writeBool(m_isBase);
		stream->writeBool(m_isTimeOffset);

		stream->writeBool(m_useAdaptive);
		stream->writeInt(m_sampling_iter);

		stream->writeBool(m_disableGradients);
	}
};



/* ==================================================================== */
/*                         Integrator                         */
/* ==================================================================== */


 
class GradientPathIntegrator : public MonteCarloIntegrator {
public:
	GradientPathIntegrator(const Properties &props);

	/// Unserialize from a binary data stream
	GradientPathIntegrator(Stream *stream, InstanceManager *manager);


	/// Starts the rendering process.
	bool render(Scene *scene,
		RenderQueue *queue, const RenderJob *job,
		int sceneResID, int sensorResID, int samplerResID);


	/// Renders a block in the image.
	void renderBlock(const Scene *scene, const Sensor *sensor, Sampler *sampler, MotionMap *motionMap, SamplingMap *samplingMap, GPTWorkResult *block,
		const bool &stop, const std::vector< TPoint2<uint8_t> > &points) const;

	void serialize(Stream *stream, InstanceManager *manager) const;
	std::string toString() const;


	/// Used by Mitsuba for initializing sub-surface scattering.
	Spectrum Li(const RayDifferential &ray, RadianceQueryRecord &rRec) const;

	
	MTS_DECLARE_CLASS()

protected:

	
private:
	GradientPathTracerConfig m_config; 

};


MTS_NAMESPACE_END

#endif /* __GBDPT_H */
