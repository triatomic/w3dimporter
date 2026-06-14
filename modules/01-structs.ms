struct HierarchyHeader
(
	version,
	hierName,
	pivotCount,
	centrePos
)

struct HierarchyPivot
(
	pivotName,
	parentID,
	pos,
	eulerAngles,
	rotation
)

struct Hierarchy
(
	header,
	pivots
)

struct AnimationHeader
(
	version,
	animName,
	skelName,
	frameCount,
	frameRate
)

struct CompressedAnimationHeader
(
	version,
	animName,
	skelName,
	frameCount,
	frameRate,
	flavour
)

struct AnimationChannel
(
	firstFrame,
	lastFrame,
	vectorLen,
	flags,
	pivotID,
	pad,
	values
)

struct AnimationTimeCodedKey
(
	keyTime,
	keyValue
)

struct AnimationTimeCodedChannel
(
	type,
	timeCodesCount,
	pivotID,
	vectorLen,
	flags,
	values
)

struct AnimationAdaptiveDeltaChannel
(
	type,
	framesCount,
	pivotID,
	vectorLen,
	flags,
	initDelta,
	increment,
	values
)

struct adInterval
(
	coef,
	startInterval,
	endInterval
)

struct AnimationBitChannel
(
	firstFrame,
	lastFrame,
	flags,
	pivotID,
	defaultVal,
	values
)

struct Animation
(
	header,
	channels,
	bitChannels
)

struct W3dMeshHeader
(
	version, attrs, meshName, containerName,
	faceCount, vertCount, matlCount, damageStageCount,
	sortLevel, prelitVersion, futureCount, vertChannelCount, faceChannelCount,
	minCorner, maxCorner, sphCentre, sphRadius
)

struct W3dMeshFace
(
	vertIds,
	attrs,
	normal,
	distance
)

struct W3dMeshMaterialSetInfo
(
	passCount,
	vertMatlCount,
	shaderCount,
	textureCount
)
struct W3dMeshShader
(
	depthCompare, depthMask, colorMask, destBlend, fogFunc, priGradient, secGradient, srcBlend, texturing,
	detailColorFunc, detailAlphaFunc, shaderPreset, alphaTest, postDetailColorFunc, postDetailAlphaFunc, pad
)

struct W3dMeshVertMaterialInfo
(
	attrs,
	ambient,
	diffuse,
	specular,
	emissive,
	shininess,
	opacity,
	translucency
)

struct W3dMeshVertMaterial
(
	vmName,
	vmInfo,
	vmArgs0,
	vmArgs1
)

struct W3dMeshTextureInfo
(
	attrs,
	animType,
	frameCount,
	frameRate
)

struct W3dMeshTexture
(
	txFileName,
	txInfo
)

struct W3dMeshTextureCoord
(
	u, v
)

struct W3dMeshTextureStage
(
	txIds,
	txCoords
)

struct W3dMeshMaterialPass
(
	vmIds,
	shaderIds,
	textureStage,	-- legacy: first stage (== textureStages[1] when present); kept for back-compat readers
	textureStages	-- array of W3dMeshTextureStage, one per W3D_CHUNK_TEXTURE_STAGE in this pass
)

struct W3dMeshVertInfs
(
	boneIds1,
	boneIds2,
	boneWgts1,
	boneWgts2
)

struct W3dMesh
(
	header,
	verts,
	normals,
	vertInfs,
	faces,
	shadeIds,
	matlheader,
	shaders,
	vertMatls,
	textures,
	matlPass,
	matlPasses
)

struct HLodHeader
(
	version,
	lodCount,
	hlodName,
	hierarchyName
)

struct HLodObjectArrayHeader
(
	modelCount,
	maxScreenSize
)

struct HLodObject
(
	pivotIndex,
	lodName
)

struct HLodObjectArray
(
	header,
	lodObjects
)

struct HLodAggregate  --renegade
(
	pivotIndex,
	name
)

struct HLod
(
	header,
	lodArray,
	lodArrays,   --renegade: all LOD levels (lodArray == lodArrays[1] for Generals compat)
	aggregates,  --renegade: 0x705 HLOD_AGGREGATE_ARRAY entries
	proxies      --renegade: 0x706 HLOD_PROXY_ARRAY entries (pivotIndex only)
)

struct AABox
(
	version,
	attrs,
	boxName,
	boxColor,
	centre,
	extent
)

struct Dependency
(
	locBone,
	Vertices
)

struct DependencyStack
(
	locMesh,
	Dependencies
)

