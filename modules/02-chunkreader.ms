fn GetChunkSize chunkSize =
( result = bit.and chunkSize 0x7FFFFFFF )

fn ReadLongArray fstream arrayEnd=
(
	longArray = #()
	while (ftell fstream < arrayEnd) do
	( append longArray (ReadLong fstream #unsigned) )
	return longArray
)

fn ReadShortArray fstream arrayEnd=
(
	shortArray = #()
	while (ftell fstream < arrayEnd) do
	(
		shortArray[shortArray.count+1] = ReadShort fstream #unsigned
	)
	return shortArray
)

fn ReadFixedString fstream =
(
	strend = (ftell fstream) + 16
	instr = ReadString fstream
	fseek fstream strend #seek_set
	result = instr
)

fn ReadLongFixedString fstream =
(
	strend = (ftell fstream) + 32
	instr = ReadString fstream
	fseek fstream strend #seek_set
	result = instr
)

fn ReadColor fstream =
(
	r = ReadByte fstream #unsigned
	g = ReadByte fstream #unsigned
	b = ReadByte fstream #unsigned
	a = ReadByte fstream #unsigned
	result = Color r g b a
	--the following code will miss one byte sometime. but why?
	--result = Color (ReadByte fstream #unsigned) (ReadByte fstream #unsigned) (ReadByte fstream #unsigned) (ReadByte fstream #unsigned)
)

fn ReadHierarchyHeader fstream =
(
	version = ReadLong fstream #unsigned
	hierName = ReadFixedString fstream
	pivotCount = ReadLong fstream #unsigned
	centrePos = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	result = HierarchyHeader version hierName pivotCount centrePos
	--return result
)

fn ReadHierarchyPivots fstream pivotsEnd =
(
	pivots = #()
	while (ftell fstream < pivotsEnd) do
	(
		pivotName = ReadFixedString fstream
		parentID = ReadLong fstream #unsigned	-- 0xffffffff = root pivot; no parent
		--if parentID != 0xffffffff do parentID += 1
		pos = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- translation to pivot point
		eulerAngles = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- orientation of the pivot point
		rotation = Quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- orientation of the pivot point
		pivots[(pivots.count + 1)] = HierarchyPivot pivotName parentID pos eulerAngles rotation
	)
	result = pivots
	--return result
)

fn ReadHierarchy fstream chunkEnd =
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		------ debug start ------
		--print ("Type: 0x" + (bit.intAsHex chunkType))
		--chunkSize = ReadLong fstream
		--print ("Size: 0x" + (bit.intAsHex chunkSize))
		--chunkSize = GetChunkSize(chunkSize)
		--print (bit.intAsHex chunkSize)
		------ debug end ------
		case chunkType of
		(
			0x00000101:	--W3D_CHUNK_HIERARCHY_HEADER
			(
				header = ReadHierarchyHeader fstream
			)
			0x00000102:	--W3D_CHUNK_PIVOTS
			(
				subChunkEnd = (ftell fstream) + chunkSize
				pivots = ReadHierarchyPivots fstream subChunkEnd
			)
			0x00000103:	--W3D_CHUNK_PIVOT_FIXUPS	-- only needed by the exporter...
			(
				--fixups[(fixups.count + 1)] = ReadHierarchyFixUps fstream
				--cracked format: there are 64 bytes in 12 dwords in 3 channels in each fixup.
				--channel X : ScaleX, Unknown, Unknown, Unknown (Long/DWord)
				--channel Y : ScaleY, Unknown, Unknown, Unknown (Long/DWord)
				--channel Z : ScaleZ, Unknown, Unknown, Unknown (Long/DWord)
				fseek fstream chunkSize #seek_cur
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
		------ debug start ------
		--print ("Pos: 0x" + (bit.intAsHex (ftell fstream)))
		--print ("End: 0x" + (bit.intAsHex chunkEnd))
		------ debug end ------
	)
	result = Hierarchy header pivots
	--return result
)

fn ReadAnimationHeader fstream =
(
	version = ReadLong fstream #unsigned
	animName = ReadFixedString fstream
	skelName = ReadFixedString fstream
	frameCount = ReadLong fstream #unsigned
	frameRate = ReadLong fstream #unsigned
	result = AnimationHeader version animName skelName frameCount frameRate
	--return result
)

fn ReadCompressedAnimationHeader fstream =
(
	version = ReadLong fstream #unsigned
	animName = ReadFixedString fstream
	skelName = ReadFixedString fstream
	frameCount = ReadLong fstream #unsigned
	frameRate = ReadShort fstream #unsigned
	flavour = ReadShort fstream #unsigned
	result = CompressedAnimationHeader version animName skelName frameCount frameRate flavour
	--return result
)

fn ReadAnimationChannel fstream chunkEnd =
(
	firstFrame = ReadShort fstream #unsigned
	lastFrame = ReadShort fstream #unsigned
	vectorLen = ReadShort fstream #unsigned
	flags = ReadShort fstream #unsigned
	pivotID = ReadShort fstream #unsigned
	--if pivotID != 0xffffffff then pivotID += 1 -- v1.00, cancelled at v1.04
	pad = ReadShort fstream #unsigned
	values = #()
	i = 1
	while (ftell fstream < chunkEnd) do
	(
		case flags of
		(
			0x0006: --ANIM_CHANNEL_Q
				values[i] = quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
			default: --ANIM_CHANNEL_X/Y/Z
				values[i] = ReadFloat fstream
		)
		i += 1
	)
	result = AnimationChannel firstFrame lastFrame vectorLen flags pivotID pad values
	--return result
)

fn ReadAnimationTimeCodedChannel fstream chunkEnd =
(
	timeCodesCount = ReadLong fstream #unsigned
	pivotID = ReadShort fstream #unsigned
	vectorLen = ReadByte fstream #unsigned
	flags = ReadByte fstream #unsigned
	values = #()
	i = 1
	while (ftell fstream < chunkEnd) do
	(
		-- Bit 31 of the timecode is W3D_TIMECODED_BINARY_MOVEMENT_FLAG (w3d.h):
		-- it marks a non-interpolated key, it is NOT part of the frame number.
		-- Left unmasked it yields keyTime ~2.1e9 and the per-frame fill loop in
		-- the playback code effectively hangs Max.
		tCode = bit.and (ReadLong fstream #unsigned) 0x7FFFFFFF
		case flags of
		(
			0x0006: --ANIM_CHANNEL_TIMECODED_Q
				tValue = quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
			default: --ANIM_CHANNEL_TIMECODED_X/Y/Z
				tValue = ReadFloat fstream
		)
		values[i] = AnimationTimeCodedKey tCode tValue
		i += 1
	)
	result = AnimationTimeCodedChannel 1 timeCodesCount pivotID vectorLen flags values
	--return result
)

fn procDeltaBlockData fstream nBits scale initVal =
(
	procData = #()
	v0 = initVal

	for i=1 to 2*nBits do
	(
		currByte = readByte fstream #unsigned

		if (nBits == 4) then
		(
			-- Splitting the byte into halves
			lVal = bit.and currByte 0x0F
			uVal = bit.shift currByte -4

			-- Restoring halves' signs (bit flipping)
			if (lVal >= 8) do lVal -= 16
			if (uVal >= 8) do uVal -= 16

			append procData (v0 + scale*lVal)
			v0 += scale*lVal
			append procData (v0 + scale*uVal)
			v0 += scale*uVal
		)
		else
		(
			currByte += 128
			if (currByte >= 128) do currByte -= 256
			append procData (v0 + scale*currByte)
			v0 += scale*currByte
		)
	)

	return procData
)

fn ReadAnimationCompressedMotionChannel fstream chunkEnd =
(
	fseek fstream 1 #seek_cur -- skipping a zero byte
	chnType = readByte fstream #unsigned
	keyFrameChn = (chnType == 0)
	vectorLen = readByte fstream #unsigned

	flags = readByte fstream #unsigned
	values = #()

	nTimeCodes = readShort fstream #unsigned
	pivotID = readShort fstream #unsigned

	-- Simple time key channel
	if (keyFrameChn) then
	(
		for i=1 to nTimeCodes do
		(
			tCode = readShort fstream #unsigned
			values[i] = AnimationTimeCodedKey tCode 0
		)

		if ((mod nTimeCodes 2) != 0) do --skipping padding
		( fseek fstream 2 #seek_cur )

		for i=1 to nTimeCodes do
		(
			case flags of
			(
				0x0006: --ANIM_CHANNEL_TIMECODED_Q
					values[i].keyValue = quat (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
				default: --ANIM_CHANNEL_TIMECODED_X/Y/Z
					values[i].keyValue = readFloat fstream
			)
		)

		result = AnimationTimeCodedChannel 1 nTimeCodes pivotID vectorLen flags values
		return result
	)

	-- Adaptive delta channel
	scale = readFloat fstream
	nBits = 4*chnType
	nBlocks = bit.shift (nTimeCodes+15) -4 -- In how many sections are data encoded? +15 is to make sure we start from 1

	scaleFactor = float 1
	if (nBits == 8) do
	( scaleFactor /= 16 )

	decData = #()
	values = #()
	deltaTableIx = 0

	case flags of
	(
		0x0006: --ANIM_MOTION_CHANNEL_DELTA_Q
		(
			decData[1] = #(readFloat fstream)
			decData[2] = #(readFloat fstream)
			decData[3] = #(readFloat fstream)
			decData[4] = #(readFloat fstream)

			for i=1 to nBlocks do
			(
				for j=1 to 4 do
				(
					deltaTableIx = readByte fstream #unsigned
					deltaScale = scale * scaleFactor * deltaTable[deltaTableIx+1]
					if (deltaTableIx <= 15) do deltaScale /= 100

					join decData[j] (procDeltaBlockData fstream nBits deltaScale decData[j][decData[j].count])
				)
			)

			decData[1].count = nTimeCodes
			decData[2].count = nTimeCodes
			decData[3].count = nTimeCodes
			decData[4].count = nTimeCodes

			for t=1 to decData[1].count do
			( values[t] = AnimationTimeCodedKey (t-1) (quat decData[1][t] decData[2][t] decData[3][t] decData[4][t]) )
		)
		default: --ANIM_MOTION_CHANNEL_DELTA_X/Y/Z
		(
			decData[1] = ReadFloat fstream

			for i=1 to nBlocks do
			(
				deltaTableIx = readByte fstream #unsigned
				deltaScale = scale * scaleFactor * deltaTable[deltaTableIx+1]
				if (deltaTableIx <= 15) do deltaScale /= 100

				join decData (procDeltaBlockData fstream nBits deltaScale decData[decData.count])
			)

			decData.count = nTimeCodes

			for t=1 to decData.count do
			( values[t] = AnimationTimeCodedKey (t-1) (decData[t]) )
		)
	)

	result = AnimationTimeCodedChannel 1 nTimeCodes pivotID vectorLen flags values
	return result
)

fn ReadAnimationBitChannel fstream chunkEnd =
(
	firstFrame = ReadShort fstream #unsigned
	lastFrame = ReadShort fstream #unsigned
	flags = ReadShort fstream #unsigned
	pivotID = ReadShort fstream #unsigned
	--if pivotID != 0xffffffff then pivotID += 1 -- v.100 cancelled at v.104
	defaultVal = ReadByte fstream #unsigned
	values = #()
	i = 1
	while (ftell fstream < chunkEnd) do
	(
		values[i] = ReadByte fstream #unsigned
		i += 1
	)
	result = AnimationBitChannel firstFrame lastFrame flags pivotID defaultVal values
)

--fn ReadAnimationTimeCodedBitChannel fstream chunkEnd =
--(
--	timeCodesCount = ReadLong fstream #unsigned
--	pivotID = ReadShort fstream #unsigned
--	flags = ReadByte fstream #unsigned
--	defaultVal = ReadByte fstream #unsigned
--	values = #()
--	i = 1
--	while (ftell fstream < chunkEnd) do
--	(
--		values[i] = ReadByte fstream #unsigned
--		i += 1
--	)
--	result = AnimationBitChannel firstFrame lastFrame flags pivotID defaultVal values
--	--return result
--)

fn ReadAnimation fstream chunkEnd =
(
	channels = #()
	bitchannels = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000201:	--W3D_CHUNK_ANIMATION_HEADER
			(
				header = ReadAnimationHeader fstream
			)
			0x00000202:	--W3D_CHUNK_ANIMATION_CHANNEL	-- channel of vectors
			(
				subChunkEnd = (ftell fstream) + chunkSize
				channels[(channels.count + 1)] = ReadAnimationChannel fstream subChunkEnd --frameCount
			)
			0x00000203:	--W3D_CHUNK_BIT_CHANNEL	-- channel of boolean values (e.g. visibility)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				bitchannels[(bitchannels.count + 1)] = ReadAnimationBitChannel fstream subChunkEnd
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
		------ debug start ------
		--print ("type: " + bit.intAsHex chunkType)
		--print ("pos: " + bit.intAsHex (ftell fstream))
		--print ("end: " + bit.intAsHex chunkEnd)
		------ debug end ------
	)
	result = Animation header channels bitchannels
	--return result
)

fn ReadCompressedAnimation fstream chunkEnd =
(
	channels = #()
	bitchannels = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000281:	--W3D_CHUNK_COMPRESSED_ANIMATION_HEADER
			(
				header = ReadCompressedAnimationHeader fstream
			)
			0x00000282:	--W3D_CHUNK_COMPRESSED_ANIMATION_CHANNEL	-- channel of vectors
			(
				subChunkEnd = (ftell fstream) + chunkSize
				if header != undefined then
					animMode = header.flavour
				else
					animMode = -1
				case animMode of
				(
					0x0: --ANIM_FLAVOUR_TIMECODED
					(
						channels[(channels.count + 1)] = ReadAnimationTimeCodedChannel fstream subChunkEnd --frameCount
					)
					0x1: --ANIM_FLAVOUR_ADAPTIVE_DELTA
					(
						-- Deliberately not imported (roadmap decision: modders don't
						-- author compressed anims). The old empty arm never advanced
						-- the stream, so the next loop iteration parsed channel DATA
						-- as chunk headers and derailed the rest of the file --
						-- skip explicitly and record the loss.
						if w3dSkippedContent != undefined do append w3dSkippedContent "adaptive-delta compressed animation channel -- animation not imported"
						fseek fstream subChunkEnd #seek_set
					)
					default: --unknown flavour: skip safely, never derail the parse
					( fseek fstream subChunkEnd #seek_set )
				)
			)
			0x00000283:	--W3D_CHUNK_COMPRESSED_BIT_CHANNEL	-- timecoded visibility
			(
				if w3dSkippedContent != undefined do append w3dSkippedContent "timecoded visibility bit channel (COMPRESSED_BIT_CHANNEL) -- not imported"
				fseek fstream chunkSize #seek_cur
			)
			0x00000284:	--W3D_CHUNK_COMPRESSED_ADAPTIVE_DELTA_MOTION_ANIMATION_CHANNEL
			(
				subChunkEnd = (ftell fstream) + chunkSize
				if header != undefined then
					animMode = header.flavour
				else
					animMode = -1
				case animMode of
				(
					0x0: --ANIM_FLAVOUR_TIMECODED
					( channels[(channels.count + 1)] = ReadAnimationCompressedMotionChannel fstream subChunkEnd )
					default: --adaptive-delta / unknown: skip safely (see 0x282 note)
					(
						if w3dSkippedContent != undefined do append w3dSkippedContent "adaptive-delta compressed animation channel -- animation not imported"
						fseek fstream subChunkEnd #seek_set
					)
				)
			)
			default:
			( fseek fstream chunkSize #seek_cur )
		)
	)
	result = Animation header channels bitchannels
	--return result
)

-- Decode a raw W3D_MESH_HEADER3.Attributes (or W3DBOX.Attributes) word into a list
-- of human-readable W3D Tools property names. Used by the "Import extended W3D
-- Info" debug log so the user can see exactly which bits the .w3d encoded and
-- which properties wwSetFlags / wwSetSorting will toggle on the imported nodes.
-- Constants mirror src\scripts\w3d.h.
fn cfDecodeW3DAttrs a =
(
	local parts = #()
	local gt = bit.and a 0x00FF0000	-- W3D_MESH_FLAG_GEOMETRY_TYPE_MASK
	case gt of
	(
		0x00000000:	append parts "GeomType=Normal"
		0x00010000:	append parts "GeomType=CamParal"
		0x00020000:	append parts "GeomType=Skin"
		0x00040000:	append parts "GeomType=AABox"
		0x00050000:	append parts "GeomType=OBBox"
		0x00060000:	append parts "GeomType=CamOrient"
		0x00070000:	append parts "GeomType=CamZOrient"
		default:	append parts ("GeomType=0x" + (bit.intAsHex gt))
	)
	if (bit.and a 0x00001000) != 0 do append parts "Hide"
	if (bit.and a 0x00002000) != 0 do append parts "TwoSided"
	if (bit.and a 0x00008000) != 0 do append parts "CastShadow"
	if (bit.and a 0x10000000) != 0 do append parts "Shatter"
	if (bit.and a 0x20000000) != 0 do append parts "Tangents"
	if (bit.and a 0x40000000) != 0 do append parts "Prelit"
	if (bit.and a 0x80000000) != 0 do append parts "AlwaysDynLight"
	-- Collision bits (W3D_MESH_FLAG_COLLISION_TYPE_MASK = 0x00000FF0).
	if (bit.and a 0x00000010) != 0 do append parts "Coll:Physical"
	if (bit.and a 0x00000020) != 0 do append parts "Coll:Projectile"
	if (bit.and a 0x00000040) != 0 do append parts "Coll:Vis"
	if (bit.and a 0x00000080) != 0 do append parts "Coll:Camera"
	if (bit.and a 0x00000100) != 0 do append parts "Coll:Vehicle"
	-- W3DBOX-only attribute bits.
	if (bit.and a 0x00000001) != 0 do append parts "Box:Aligned"
	if (bit.and a 0x00000002) != 0 do append parts "Box:Oriented"
	return parts
)

fn ReadMeshHeader fstream =
(
	version = ReadLong fstream #unsigned
	attrs = ReadLong fstream #unsigned
	meshName = ReadFixedString fstream
	containerName = ReadFixedString fstream
	-- Counts, these can be regarded as an inventory of what is to come in the file.
	faceCount = ReadLong fstream #unsigned	--number of triangles
	vertCount = ReadLong fstream #unsigned	--number of unique vertices
	matlCount = ReadLong fstream #unsigned	--number of unique materials
	damageStageCount = ReadLong fstream #unsigned	--number of damage offset chunks
	sortLevel = ReadLong fstream #unsigned	--static sorting level of this mesh
	prelitVersion = ReadLong fstream #unsigned	--mesh generated by this version of Lightmap Tool
	futureCount = ReadLong fstream #unsigned	--future counts
	vertChannelCount = ReadLong fstream #unsigned	--bits for presence of types of per-vertex info
	faceChannelCount = ReadLong fstream #unsigned	--bits for presence of types of per-face info
	-- Bounding volumes
	minCorner = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	--Min corner of the bounding box
	maxCorner = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	--Max corner of the bounding box
	sphCentre = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	--Centre of bounding sphere
	sphRadius = ReadFloat fstream	--Bounding sphere radius
	result = W3dMeshHeader version attrs meshName containerName faceCount vertCount matlCount damageStageCount sortLevel prelitVersion futureCount vertChannelCount faceChannelCount minCorner maxCorner sphCentre sphRadius
)

fn ReadMeshVertArray fstream chunkEnd =
(
	verts = #()
	while (ftell fstream < chunkEnd) do
	(
		verts[verts.count+1] = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	)
	return verts
)

fn ReadMeshFace fstream =
(
	--vertIds = #()
	--vertIds[1] = ReadLong fstream #unsigned	-- vertex,vnormal,texcoord,color indices
	--vertIds[2] = ReadLong fstream #unsigned
	--vertIds[3] = ReadLong fstream #unsigned
	vertIds = Point3 (ReadLong fstream #unsigned) (ReadLong fstream #unsigned) (ReadLong fstream #unsigned)
	attrs = ReadLong fstream #unsigned	-- attributes bits
	normal = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)	-- plane normal
	distance = ReadFloat fstream	-- plane distance
	result = W3dMeshFace vertIds attrs normal distance
)

fn ReadMeshFaceArray fstream chunkEnd =
(
	faces = #()
	while (ftell fstream < chunkEnd) do
	( append faces (ReadMeshFace fstream) )
	return faces
)

--replaced by ReadLongArray since v1.02
--fn ReadMeshVertShadeIds fstream chunkEnd =
--(
--	shadeIds = #()
--	while (ftell fstream < chunkEnd) do
--	(
--		shadeIds[shadeIds.count+1] = ReadLong fstream #unsigned
--	)
--	return shadeIds
--)

fn ReadMeshVertInfs fstream chunkEnd =
(
	boneIds1 = #()
	boneIds2 = #()
	boneWgts1 = #()
	boneWgts2 = #()
	while (ftell fstream < chunkEnd) do
	(
		append boneIds1 (ReadShort fstream #unsigned)
		append boneIds2 (ReadShort fstream #unsigned)
		append boneWgts1 (ReadShort fstream #unsigned)
		append boneWgts2 (ReadShort fstream #unsigned)

		--if (boneIds2[boneIds2.count] > 0) do break()
		--fseek fstream 6 #seek_cur --skip pad 6 bytes
	)
	return W3dMeshVertInfs boneIds1 boneIds2 boneWgts1 boneWgts2
)

fn ReadMeshMaterialSetInfo fstream chunkEnd =
(
	passCount = ReadLong fstream #unsigned	--how many material passes this render object uses
	vertMatlCount = ReadLong fstream #unsigned	--how many vertex materials are used
	shaderCount = ReadLong fstream #unsigned	--how many shaders are used
	textureCount = ReadLong fstream #unsigned	--how many textures are used
	result = W3dMeshMaterialSetInfo passCount vertMatlCount shaderCount textureCount
)

fn ReadMeshShader fstream =
(
	depthCompare = ReadByte fstream #unsigned
	depthMask = ReadByte fstream #unsigned
	colorMask = ReadByte fstream #unsigned	--now obsolete and ignored
	destBlend = ReadByte fstream #unsigned
	fogFunc = ReadByte fstream #unsigned	--now obsolete and ignored
	priGradient = ReadByte fstream #unsigned
	secGradient = ReadByte fstream #unsigned
	srcBlend = ReadByte fstream #unsigned
	texturing = ReadByte fstream #unsigned
	detailColorFunc = ReadByte fstream #unsigned
	detailAlphaFunc = ReadByte fstream #unsigned
	shaderPreset = ReadByte fstream #unsigned	--now obsolete and ignored
	alphaTest = ReadByte fstream #unsigned
	postDetailColorFunc = ReadByte fstream #unsigned
	postDetailAlphaFunc = ReadByte fstream #unsigned
	pad = ReadByte fstream #unsigned
	result = W3dMeshShader depthCompare depthMask colorMask destBlend fogFunc priGradient secGradient srcBlend texturing detailColorFunc detailAlphaFunc shaderPreset alphaTest postDetailColorFunc postDetailAlphaFunc pad
)

fn ReadMeshShaderArray fstream chunkEnd =
(
	shaders = #()
	while (ftell fstream < chunkEnd) do
	(
		shaders[shaders.count+1] = ReadMeshShader fstream
	)
	return shaders
)

fn ReadMeshVertMaterialInfo fstream =
(
	attrs = ReadLong fstream #unsigned	-- bitfield for the flags defined above
	ambient = ReadColor fstream
	diffuse = ReadColor fstream
	specular = ReadColor fstream
	emissive = ReadColor fstream
	shininess = ReadFloat fstream	-- how tight the specular highlight will be, 1 - 1000 (default = 1)
	opacity = ReadFloat fstream	-- how opaque the material is, 0.0 = invisible, 1.0 = fully opaque (default = 1)
	translucency = ReadFloat fstream	-- how much light passes through the material. (default = 0)
	result = W3dMeshVertMaterialInfo attrs ambient diffuse specular emissive shininess opacity translucency
)

fn ReadMeshVertMaterial fstream chunkEnd =
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x0000002C:	--W3D_CHUNK_VERTEX_MATERIAL_NAME	--vertex material name (NULL-terminated string)
			(
				vmName = ReadString fstream
			)
			0x0000002D:	--W3D_CHUNK_VERTEX_MATERIAL_INFO	--W3dVertexMaterialStruct
			(
				vmInfo = ReadMeshVertMaterialInfo fstream
			)
			0x0000002E:	--W3D_CHUNK_VERTEX_MAPPER_ARGS0	--Null-terminated string
			(
				vmArgs0 = ReadString fstream
			)
			0x0000002F:	--W3D_CHUNK_VERTEX_MAPPER_ARGS1	--Null-terminated string
			(
				vmArgs1 = ReadString fstream
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	result = W3dMeshVertMaterial vmName vmInfo vmArgs0 vmArgs1
)

fn ReadMeshVertMaterialArray fstream chunkEnd =
(
	matls = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x0000002B:	--W3D_CHUNK_VERTEX_MATERIAL
			(
				subChunkEnd = (ftell fstream) + chunkSize
				matls[matls.count+1] = ReadMeshVertMaterial fstream subChunkEnd
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	return matls
)

fn ReadMeshTextureInfo fstream=
(
	attrs = ReadShort fstream #unsigned
	animType = ReadShort fstream #unsigned
	frameCount = ReadLong fstream #unsigned
	frameRate = ReadFloat fstream
	result = W3dMeshTextureInfo attrs animType frameCount frameRate
)

fn ReadMeshTexture fstream chunkEnd=
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000032:	--W3D_CHUNK_TEXTURE_NAME	// texture filename (NULL-terminated string)
			(
				txFileName = ReadString fstream
			)
			0x00000033:	--W3D_CHUNK_TEXTURE_INFO	// optional W3dTextureInfoStruct
			(
				txInfo = ReadMeshTextureInfo fstream
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshTexture txFileName txInfo
)

fn ReadMeshTextureArray fstream chunkEnd=
(
	textures = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000031:	--W3D_CHUNK_TEXTURE	// wraps a texture definition
			(
				subChunkEnd = (ftell fstream) + chunkSize
				textures[(textures.count + 1)] = ReadMeshTexture fstream subChunkEnd
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	return textures
)

fn ReadMeshTextureCoordArray fstream chunkEnd=
(
	txCoords = #()
	while (ftell fstream < chunkEnd) do
	(
		--u = ReadFloat fstream
		--v = ReadFloat fstream
		--txCoords[txCoords.count+1] = W3dMeshTextureCoord u v
		append txCoords (Point2 (ReadFloat fstream) (ReadFloat fstream))
	)
	return txCoords
)

fn ReadMeshTextureStage fstream chunkEnd=
(
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		case chunkType of
		(
			0x00000049:	--W3D_CHUNK_TEXTURE_IDS	// single or per-tri array of uint32 texture indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txIds = ReadLongArray fstream subChunkEnd
			)
			0x0000004A:	--W3D_CHUNK_STAGE_TEXCOORDS	// per-vertex texture coordinates (array of W3dTexCoordStruct's)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txCoords = ReadMeshTextureCoordArray fstream subChunkEnd
			)
			--0x0000004B:	--W3D_CHUNK_PER_FACE_TEXCOORD_IDS	// indices to W3D_CHUNK_STAGE_TEXCOORDS, (array of Vector3i)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshTextureStage txIds txCoords
)

fn ReadMeshDCGArray fstream chunkEnd =
(
	-- per-vertex diffuse colors (W3D_CHUNK_DCG): an array of W3dRGBAStruct
	-- (4 bytes R,G,B,A each), one entry per mesh vertex. ReadColor already reads
	-- exactly that layout, so this mirrors ReadMeshTextureCoordArray above.
	dcg = #()
	while (ftell fstream < chunkEnd) do
	( append dcg (ReadColor fstream) )
	return dcg
)

fn ReadMeshMaterialPass fstream chunkEnd=
(
	-- A MATERIAL_PASS may contain multiple TEXTURE_STAGE sub-chunks (stage 0, stage 1, ...).
	-- Collect them all; expose stages[1] as the legacy `textureStage` field for back-compat.
	local txStages = #()
	local txStage = undefined
	-- per-vertex diffuse colors (W3D_CHUNK_DCG); undefined when the pass has none.
	-- Declared local (unlike vmIds/shaderIds, which are bare) so it can never leak
	-- a previous mesh/pass's colors into a pass that omits the chunk.
	local dcg = undefined
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		tempMatl = ftell fstream
		case chunkType of
		(
			0x00000039:	--W3D_CHUNK_VERTEX_MATERIAL_IDS	// single or per-vertex array of uint32 vertex material indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				vmIds = ReadLongArray fstream subChunkEnd
			)
			0x0000003F:	--W3D_CHUNK_VERTEX_MATERIAL_IDS (NEW)	// single or per-vertex array of uint32 vertex material indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				vmIds = ReadLongArray fstream subChunkEnd
				shaderIds = #()
				join shaderIds vmIds
			)
			0x0000003A:	--W3D_CHUNK_SHADER_IDS	// single or per-tri array of uint32 shader indices (check chunk size)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				shaderIds = ReadLongArray fstream subChunkEnd
			)
			0x0000003B:	--W3D_CHUNK_DCG	// per-vertex diffuse color values (array of W3dRGBAStruct's)
			(
				subChunkEnd = (ftell fstream) + chunkSize
				dcg = ReadMeshDCGArray fstream subChunkEnd
			)
			0x0000003C:	--W3D_CHUNK_DIG	// per-vertex diffuse illumination (baked lighting)
			(
				-- Not yet applied (roadmap P4: both engines multiply DIG into the
				-- vertex color array at load) -- record the skip so the loss shows
				-- in the import summary instead of the mesh just looking unlit.
				if w3dSkippedContent != undefined do append w3dSkippedContent "DIG per-vertex baked lighting -- not imported (mesh may look unlit vs in-game)"
				fseek fstream chunkSize #seek_cur
			)
			--0x0000003E:	--W3D_CHUNK_SCG	// per-vertex specular color values -- dead in BOTH engines (Renegade read_scg is a stub); intentionally ignored
			0x00000048:	--W3D_CHUNK_TEXTURE_STAGE	// wrapper around a texture stage.
			(
				subChunkEnd = (ftell fstream) + chunkSize
				local _stg = ReadMeshTextureStage fstream subChunkEnd
				append txStages _stg
				if txStage == undefined do txStage = _stg
			)
			0x0000004A:	--W3D_CHUNK_TEXTURE_STAGE (NEW)	// wrapper around a texture stage.
			(
				subChunkEnd = (ftell fstream) + chunkSize
				txIds =#()
				join txIds vmIds
				local _stg = W3dMeshTextureStage txIds (ReadMeshTextureCoordArray fstream subChunkEnd)
				append txStages _stg
				if txStage == undefined do txStage = _stg
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		) -- end case
	) -- end while
	result = W3dMeshMaterialPass vmIds shaderIds txStage txStages dcg
)

fn ReadMesh fstream chunkEnd =
(
	--bitchannels = #()
	matlPasses = #()
	userText = undefined	-- reset per mesh: an absent 0x0C must not inherit the previous mesh's note
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		subChunkEnd = (ftell fstream) + chunkSize
		case chunkType of
		(
			0x00000002:	--W3D_CHUNK_VERTICES	--array of vertices (array of W3dVectorStruct's)
			(
				verts = ReadMeshVertArray fstream subChunkEnd
			)
			0x00000003:	--W3D_CHUNK_VERTEX_NORMALS	--array of normals (array of W3dVectorStruct's)
			(
				normals = ReadMeshVertArray fstream subChunkEnd
			)
			0x0000000C:	--W3D_CHUNK_MESH_USER_TEXT	// Text from the MAX comment field (Null terminated string)
			(
				-- per-mesh authoring note (the MAX "User Defined Properties" buffer); the
				-- exporter re-emits it verbatim from that buffer, so reading it here is all
				-- that's needed for a round-trip. ReadString stops at the null; seek to the
				-- chunk end so the loop resumes cleanly regardless of any trailing padding.
				userText = ReadString fstream
				fseek fstream subChunkEnd #seek_set
			)
			0x0000000E:	--W3D_CHUNK_VERTEX_INFLUENCES	--Mesh Deformation vertex connections (array of W3dVertInfStruct's)
			(
				vertInfs = ReadMeshVertInfs fstream subChunkEnd
			)
			0x0000001F:	--W3D_CHUNK_MESH_HEADER3	--mesh header contains general info about the mesh.
			(
				header = ReadMeshHeader fstream
			)
			0x00000020:	--W3D_CHUNK_TRIANGLES	--new improved triangles chunk (array of W3dTriangleStruct's)
			(
				faces = ReadMeshFaceArray fstream subChunkEnd
			)
			0x00000022:	--W3D_CHUNK_VERTEX_SHADE_INDICES	--shade indexes for each vertex (array of uint32's)
			(
				shadeIds = ReadLongArray fstream subChunkEnd
			)
			--0x00000023:	--W3D_CHUNK_PRELIT_UNLIT	// optional unlit material chunk wrapper
			-- // renegade part of the code
			-- W3D_CHUNK_PRELIT_VERTEX (0x24) wraps the same MATERIAL_INFO/SHADERS/
			-- VERTEX_MATERIALS/TEXTURES/MATERIAL_PASS chunks a non-prelit mesh has at
			-- top level. Descend by NOT advancing past the wrapper -- the next loop
			-- iteration reads the inner chunks. Without this, prelit meshes (Renegade
			-- terrain in particular) fall through to the default arm and skip the
			-- entire material block.
			0x00000024: ()  -- W3D_CHUNK_PRELIT_VERTEX: descend (no-op; do not advance)
			-- Lightmap prelit variants are still skipped (real handling needs
			-- lightmap textures + secondary UVs, not a wrapper descend) -- but
			-- record the skip so the import summary surfaces the loss. Both
			-- engines prefer these at render (shipped Renegade defaults to
			-- PRELIT_MODE_LIGHTMAP_MULTI_PASS, ww3d.cpp:204).
			0x00000025:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_PASS
			(
				if w3dSkippedContent != undefined do append w3dSkippedContent "lightmap prelit variant (PRELIT_LIGHTMAP_MULTI_PASS) -- baked lightmaps not imported"
				fseek fstream chunkSize #seek_cur
			)
			0x00000026:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_TEXTURE
			(
				if w3dSkippedContent != undefined do append w3dSkippedContent "lightmap prelit variant (PRELIT_LIGHTMAP_MULTI_TEXTURE) -- baked lightmaps not imported"
				fseek fstream chunkSize #seek_cur
			)
			0x00000028:	--W3D_CHUNK_MATERIAL_INFO	--materials information, pass count, etc (contains W3dMaterialInfoStruct)
			(
				matlheader = ReadMeshMaterialSetInfo fstream subChunkEnd
			)
			0x00000029:	--W3D_CHUNK_SHADERS	--shaders (array of W3dShaderStruct's)
			(
				shaders = ReadMeshShaderArray fstream subChunkEnd
			)
			0x0000002A:	--W3D_CHUNK_VERTEX_MATERIALS	--wraps the vertex materials
			(
				vertMatls = ReadMeshVertMaterialArray fstream subChunkEnd
			)
			0x00000030:	--W3D_CHUNK_TEXTURES	--wraps all of the texture info
			(
				textures = ReadMeshTextureArray fstream subChunkEnd
			)
			0x00000038:	--W3D_CHUNK_MATERIAL_PASS	--wraps the information for a single material pass
			(
				matlPass = ReadMeshMaterialPass fstream subChunkEnd
				append matlPasses matlPass
			)
			--0x00000058:	--W3D_CHUNK_DEFORM	// mesh deform or 'damage' information.
			--0x00000080:	--W3D_CHUNK_PS2_SHADERS	// Shader info specific to the Playstation 2.
			--0x00000090:	--W3D_CHUNK_AABTREE	// Axis-Aligned Box Tree for hierarchical polygon culling
			--0x00000026:	--W3D_CHUNK_PRELIT_LIGHTMAP_MULTI_TEXTURE	// optional lightmapped multi-texture material chunk wrapper
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
		------ debug start ------
		--print ("type: " + bit.intAsHex chunkType)
		--print ("pos: " + bit.intAsHex (ftell fstream))
		--print ("end: " + bit.intAsHex chunkEnd)
		------ debug end ------
	)
	result = W3dMesh header verts normals vertInfs faces shadeIds matlheader shaders vertMatls textures matlPass matlPasses userText
	--return result
)

fn ReadHLodHeader fstream =
(
	version = ReadLong fstream #unsigned
	lodCount = ReadLong fstream #unsigned
	hlodName = ReadFixedString fstream
	hierarchyName = ReadFixedString fstream	-- name of the hierarchy tree to use (\0 if none)
	result = HLodHeader version lodCount hlodName hierarchyName
)

fn ReadHLodObjectArrayHeader fstream =
(
	modelCount = ReadLong fstream #unsigned
	maxScreenSize = ReadLong fstream #unsigned	-- if model is bigger than this, switch to higher lod.
	result = HLodObjectArrayHeader modelCount maxScreenSize
)

fn ReadHLodObject fstream chunkEnd =
(
	pivotIndex = ReadLong fstream #unsigned
	lodName = ReadString fstream
	fseek fstream chunkEnd #seek_set -- skip object full name 32 bytes
	result = HLodObject pivotIndex lodName
)

fn ReadHLodObjectArray fstream chunkEnd=
(
	lodObjs = #()
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		subChunkEnd = (ftell fstream) + chunkSize
		case chunkType of
		(
			0x00000703:	--W3D_CHUNK_HLOD_SUB_OBJECT_ARRAY_HEADER	// info on the objects in this level of detail array
			(
				header = ReadHLodObjectArrayHeader fstream
			)
			0x00000704:	--W3D_CHUNK_HLOD_SUB_OBJECT	// an object in this level of detail array
			(
				lodObjs[lodObjs.count+1] = ReadHLodObject fstream subChunkEnd
			)

			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	result = HLodObjectArray header lodObjs
)

fn ReadHLod fstream chunkEnd =
(
	local header = undefined
	local lodArray = undefined
	local lodArrays = #()
	local aggregates = #()  --renegade: HLodAggregate entries from 0x705
	local proxies = #()     --renegade: pivot indices from 0x706
	while (ftell fstream < chunkEnd) do
	(
		chunkType = ReadLong fstream #unsigned
		chunkSize = GetChunkSize(ReadLong fstream #unsigned)
		subChunkEnd = (ftell fstream) + chunkSize
		case chunkType of
		(
			0x00000701:	--W3D_CHUNK_HLOD_HEADER
			(
				header = ReadHLodHeader fstream
			)
			0x00000702:	--W3D_CHUNK_HLOD_LOD_ARRAY
			(
				local arr = ReadHLodObjectArray fstream subChunkEnd
				lodArrays[lodArrays.count + 1] = arr
				if lodArrays.count == 1 do lodArray = arr  --keep lodArray == first for Generals compat
			)
			0x00000705:	--W3D_CHUNK_HLOD_AGGREGATE_ARRAY  --renegade
			(
				while (ftell fstream < subChunkEnd) do
				(
					local subType = ReadLong fstream #unsigned
					local subSize = GetChunkSize(ReadLong fstream #unsigned)
					local subEnd  = (ftell fstream) + subSize
					case subType of
					(
						0x00000703: ( fseek fstream subSize #seek_cur )  --array header, skip
						0x00000704:  --SUB_OBJECT
						(
							local pivIdx = ReadLong fstream #unsigned
							local aName  = ReadString fstream
							fseek fstream subEnd #seek_set
							aggregates[aggregates.count + 1] = HLodAggregate pivIdx aName
						)
						default: ( fseek fstream subSize #seek_cur )
					)
				)
			)
			0x00000706:	--W3D_CHUNK_HLOD_PROXY_ARRAY  --renegade
			(
				while (ftell fstream < subChunkEnd) do
				(
					local subType = ReadLong fstream #unsigned
					local subSize = GetChunkSize(ReadLong fstream #unsigned)
					local subEnd  = (ftell fstream) + subSize
					case subType of
					(
						0x00000703: ( fseek fstream subSize #seek_cur )  --array header, skip
						0x00000704:  --SUB_OBJECT
						(
							local pivIdx = ReadLong fstream #unsigned
							local pName  = ReadString fstream
							fseek fstream subEnd #seek_set
							proxies[proxies.count + 1] = HLodAggregate pivIdx pName
						)
						default: ( fseek fstream subSize #seek_cur )
					)
				)
			)
			default:
			(
				fseek fstream chunkSize #seek_cur
			)
		)
	)
	result = HLod header lodArray lodArrays aggregates proxies
)

fn ReadAABox fstream chunkEnd =
(
	version = ReadLong fstream #unsigned
	attrs = ReadLong fstream #unsigned
	boxName = ReadLongFixedString fstream
	boxColor = ReadColor fstream
	centre = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	extent = Point3 (ReadFloat fstream) (ReadFloat fstream) (ReadFloat fstream)
	result = AABox version attrs boxName boxColor centre extent
)

rollout rltDepStackController "Dependencies" width:200 height:120
(
	dropDownList ddlMeshes "Meshes:" pos:[17,17] width:160 height:40
	dropDownList ddlBones "Bones:" pos:[17,65] width:160 height:40
	button btnSelectAllBones "Pick All Bones" pos:[33,120] width:127 height:36

	on ddlMeshes selected sel do
	(
		boneNames = #()
		for i=1 to (depStacks[ddlMeshes.selection]).Dependencies.count do
		( append boneNames (depStacks[ddlMeshes.selection]).Dependencies[i].locBone.name )
		ddlBones.items = boneNames
		select((depStacks[ddlMeshes.selection]).locMesh)
		subobjectLevel = 1
	)

	on ddlBones selected sel do
	(
		if wwBinding do
		( modPanel.setCurrentObject (depStacks[ddlMeshes.selection]).locMesh.modifiers[#WWSkin_Binding] )
		if not wwBinding do
		( select((depStacks[ddlMeshes.selection]).locMesh) )
		subobjectLevel = 1

		(depStacks[ddlMeshes.selection]).locMesh.selectedVerts = (depStacks[ddlMeshes.selection]).Dependencies[ddlBones.selection].Vertices
	)

	on btnSelectAllBones pressed do
	(
		clearSelection()
		for m=1 to depStacks.count do
		(
			for p=1 to ((depStacks[m]).Dependencies).count do
			( selectMore(((depStacks[m]).Dependencies[p]).locBone) )
		)
	)
)

--interface
--utility w3dimport "Coolfile W3D Importer"
-- rnSelection: optional struct passed by the Renegade dialog for filtered imports.
-- undefined = import everything (normal path). When set, only items whose names
-- appear in the respective arrays are built. Empty array within the struct = import all of that category.
struct RenegadeSelection
(
	meshes,       -- array of mesh names to import; empty = all
	proxies,      -- array of proxy names to import; empty = all
	aggregates,   -- array of aggregate names to import; empty = all
	importAnim  = true,   -- false = skip animation keyframes
	importBones = true,   -- false = skip hierarchy/bone creation
	bonesOnly   = false,  -- true = skip mesh geometry, build bones only
	lodMode     = -1,     -- -1 = All LODs, -2 = None, 0..N = single LOD index
	animFrom    = -1,     -- -1 = no clamp (import all frames), else 0-based first frame
	animTo      = -1,     -- -1 = no clamp,                      else 0-based last  frame
	depBonesOnly = false, -- true + non-empty .meshes -> keep only bones referenced by selected meshes' hierarchies (incl. parent ancestors)
	originBone   = false  -- true -> add a single Bone at world origin and reparent root pivots under it
)

