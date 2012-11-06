//////////////////////////////////////////////////////////////////////////
// This shader computes the lightmaps
//
#include "Inc/Global.fx"
#include "Inc/RayTracing.fx"

static const uint	GROUPS_PER_TEXEL_DIRECT = 1;	// Amount of thread groups per texel for direct lighting (must be POT)
static const uint	GROUPS_PER_TEXEL_INDIRECT = 1;	// Amount of thread groups per texel for indirect lighting (must be POT)

static const float	IRRADIANCE_WEIGHT_DIRECT = TWOPI / (GROUPS_PER_TEXEL_DIRECT << 10);		// The contribution of each radiance to the final irradiance
static const float	IRRADIANCE_WEIGHT_INDIRECT = TWOPI / (GROUPS_PER_TEXEL_INDIRECT << 10);	// The contribution of each radiance to the final irradiance

// Room description
static const float3	ROOM_SIZE = float3( 10.0, 5.0, 10.0 );		// 10x5x10 m^3
static const float3	ROOM_HALF_SIZE = 0.5 * ROOM_SIZE;
static const float3	ROOM_INV_HALF_SIZE = 1.0 / ROOM_HALF_SIZE;
static const float3	ROOM_POSITION = float3( 0.0, 2.5, 0.0 );	// 0 is the floor's height
static const float	ROOM_CEILING_HEIGHT = ROOM_POSITION.y + ROOM_HALF_SIZE.y; 

// Light description
static const float2	LIGHT_SIZE = float2( 1.0, 8.0 );
static const float3	LIGHT_NORMAL = float3( 0.0, -1.0, 0.0 );
static const float3	LIGHT_POS0 = float3( -0.5 * ROOM_SIZE.x + 1.5 + LIGHT_SIZE.x * (0.5 + 2.0 * 0), ROOM_CEILING_HEIGHT, 0.0 );
static const float3	LIGHT_POS1 = float3( -0.5 * ROOM_SIZE.x + 1.5 + LIGHT_SIZE.x * (0.5 + 2.0 * 1), ROOM_CEILING_HEIGHT, 0.0 );
static const float3	LIGHT_POS2 = float3( -0.5 * ROOM_SIZE.x + 1.5 + LIGHT_SIZE.x * (0.5 + 2.0 * 2), ROOM_CEILING_HEIGHT, 0.0 );
static const float3	LIGHT_POS3 = float3( -0.5 * ROOM_SIZE.x + 1.5 + LIGHT_SIZE.x * (0.5 + 2.0 * 3), ROOM_CEILING_HEIGHT, 0.0 );

// Wall material description
//static const float	WALL_REFLECTANCE = 0.2;###
static const float	WALL_REFLECTANCE = 1.0;
static const float	WALL_REFLECTANCE0 = WALL_REFLECTANCE;
static const float	WALL_REFLECTANCE1 = WALL_REFLECTANCE;
static const float	WALL_REFLECTANCE2 = WALL_REFLECTANCE;
static const float	WALL_REFLECTANCE3 = WALL_REFLECTANCE;
static const float	WALL_REFLECTANCE4 = WALL_REFLECTANCE;
static const float	WALL_REFLECTANCE5 = WALL_REFLECTANCE;

struct	LightMapInfos
{
	float3	Position;
	uint	Seed0;
	float3	Normal;
	uint	Seed1;
	float3	Tangent;
	uint	Seed2;
	float3	BiTangent;
	uint	Seed3;
};

struct	LightMapResult
{
	float4	Irradiance;	// Each component represents the contribution of a separate light (conveniently, there are 4 lights in the room)
};


//[
cbuffer	cbRender	: register( b10 )
{
	uint2	_LightMapSize;
};
//]

//[
StructuredBuffer<LightMapInfos>		_Input : register( t0 );
StructuredBuffer<LightMapResult>	_PreviousPass0 : register( t4 );	// The 6 light map colors from the previous pass
StructuredBuffer<LightMapResult>	_PreviousPass1 : register( t5 );
StructuredBuffer<LightMapResult>	_PreviousPass2 : register( t6 );
StructuredBuffer<LightMapResult>	_PreviousPass3 : register( t7 );
StructuredBuffer<LightMapResult>	_PreviousPass4 : register( t8 );
StructuredBuffer<LightMapResult>	_PreviousPass5 : register( t9 );

RWStructuredBuffer<LightMapResult>	_Output : register( u0 );
RWStructuredBuffer<LightMapResult>	_AccumOutput : register( u1 );
//]


//////////////////////////////////////////////////////////////////////////
// Builds the seeds for the RNGs
uint4	BuildSeed( uint _TexelIndex, LightMapInfos _Infos )
{
	return uint4(	// Modify seeds with texel index for different random values
			LCGStep( _Infos.Seed0, 37587 * _TexelIndex, 890567 ),
			LCGStep( _Infos.Seed1, 37587 * _TexelIndex, 890567 ),
			LCGStep( _Infos.Seed2, 37587 * _TexelIndex, 890567 ),
			LCGStep( _Infos.Seed3, 37587 * _TexelIndex, 890567 )
		);
}

//////////////////////////////////////////////////////////////////////////
// Computes the flattened texel/ray informations
void	ComputeTexelRayInfos( uint2 _GroupID, uint _GroupIndex, const uint _GroupsPerTexel, out uint _TexelIndex, out uint _TexelGroup, out uint _RayIndex, out uint _RaysCount )
{
	uint	TexelX = _GroupID.x / _GroupsPerTexel;		// Position of the texel on X
	uint	TexelY = _GroupID.y;

	_TexelGroup = _GroupID.x & (_GroupsPerTexel-1);		// Index of the thread group for that texel (in [0,GROUPS_PER_TEXEL-1])
	_TexelIndex = _LightMapSize.x * TexelY + TexelX;
	_RayIndex = (_TexelGroup << 10) + _GroupIndex;		// The flattened thread index
	_RaysCount = _GroupsPerTexel << 10;
}

//////////////////////////////////////////////////////////////////////////
// Direct lighting samples the 4 light sources
// Each thread casts 4 rays toward the 4 lights
//
void	GenerateRayDirect( uint _TexelIndex, uint _TexelGroup, uint _RayIndex, uint _RaysCount, inout uint4 _Seed, out float3 _Position, out float3 _Normal, out float4 _ToLight0, out float4 _ToLight1, out float4 _ToLight2, out float4 _ToLight3 )
{
	LightMapInfos	Source = _Input[_TexelIndex];

	_Position = Source.Position;
	_Normal = Source.Normal;

	// Generate positions on lights
	float2	LocalLightPos = GenerateRectanglePosition( _RayIndex, _RaysCount, _Seed, LIGHT_SIZE );
	float3	LightPos = LIGHT_POS0 + float3( LocalLightPos.x, 0.0, LocalLightPos.y );
	_ToLight0.xyz = LightPos - _Position;
	_ToLight0.w = 1.0 / dot( _ToLight0.xyz, _ToLight0.xyz );	// 1/r�
	_ToLight0.xyz *= sqrt( _ToLight0.w );

	LocalLightPos = GenerateRectanglePosition( _RayIndex, _RaysCount, _Seed, LIGHT_SIZE );
	LightPos = LIGHT_POS1 + float3( LocalLightPos.x, 0.0, LocalLightPos.y );
	_ToLight1.xyz = LightPos - _Position;
	_ToLight1.w = 1.0 / dot( _ToLight1.xyz, _ToLight1.xyz );	// 1/r�
	_ToLight1.xyz *= sqrt( _ToLight1.w );

	LocalLightPos = GenerateRectanglePosition( _RayIndex, _RaysCount, _Seed, LIGHT_SIZE );
	LightPos = LIGHT_POS2 + float3( LocalLightPos.x, 0.0, LocalLightPos.y );
	_ToLight2.xyz = LightPos - _Position;
	_ToLight2.w = 1.0 / dot( _ToLight2.xyz, _ToLight2.xyz );	// 1/r�
	_ToLight2.xyz *= sqrt( _ToLight2.w );

	LocalLightPos = GenerateRectanglePosition( _RayIndex, _RaysCount, _Seed, LIGHT_SIZE );
	LightPos = LIGHT_POS3 + float3( LocalLightPos.x, 0.0, LocalLightPos.y );
	_ToLight3.xyz = LightPos - _Position;
	_ToLight3.w = 1.0 / dot( _ToLight3.xyz, _ToLight3.xyz );	// 1/r�
	_ToLight3.xyz *= sqrt( _ToLight3.w );
}

// groupshared uint	shGroupLock = 0;	// Default is not locked
// void	InterlockedAdd( uint _UniqueID, inout float4 _Dest, float4 _Source )
// {
// 	while ( true )
// 	{
// 		uint	OriginalValue;
// 		InterlockedCompareExchange( shGroupLock, 0, _UniqueID, OriginalValue );
// 		if ( OriginalValue == 0 )
// 			break;	// We got the lock !
// 	}
// 
// 	// Accumulate
// 	_Dest += _Source;
// 
// 	// Release lock
// 	shGroupLock = 0;
// }

groupshared uint4	shSumRadianceInt;

[numthreads( 1024, 1, 1 )]
void	CS_Direct(	uint3 _GroupID			: SV_GroupID,			// Defines the group offset within a Dispatch call, per dimension of the dispatch call
					uint3 _ThreadID			: SV_DispatchThreadID,	// Defines the global thread offset within the Dispatch call, per dimension of the group
					uint3 _GroupThreadID	: SV_GroupThreadID,		// Defines the thread offset within the group, per dimension of the group
					uint  _GroupIndex		: SV_GroupIndex )		// Provides a flattened index for a given thread within a given group
{
	shSumRadianceInt = 0;
 	GroupMemoryBarrierWithGroupSync();

	uint	TexelIndex, TexelGroup, RayIndex, RaysCount;
	ComputeTexelRayInfos( _GroupID.xy, _GroupIndex.x, GROUPS_PER_TEXEL_DIRECT, TexelIndex, TexelGroup, RayIndex, RaysCount );

	uint4	Seed = BuildSeed( TexelIndex, _Input[TexelIndex] );

	// Generate the 4 rays
	float3	Position, Normal;
	float4	ToLight0, ToLight1, ToLight2, ToLight3;
	GenerateRayDirect( TexelIndex, TexelGroup, RayIndex, RaysCount, Seed, Position, Normal, ToLight0, ToLight1, ToLight2, ToLight3 );

	// Compute radiance coming from the 4 lights
	float4	Radiance = float4(	saturate( -dot( LIGHT_NORMAL, ToLight0.xyz ) ) * ToLight0.w,
								saturate( -dot( LIGHT_NORMAL, ToLight1.xyz ) ) * ToLight1.w,
								saturate( -dot( LIGHT_NORMAL, ToLight2.xyz ) ) * ToLight2.w,
								saturate( -dot( LIGHT_NORMAL, ToLight3.xyz ) ) * ToLight3.w
							 ) * saturate( dot( Normal, ToLight0.xyz ) ) * IRRADIANCE_WEIGHT_DIRECT;

//float4	Radiance = 0.5 * IRRADIANCE_WEIGHT_DIRECT;

	// Accumulate
	uint4	RadianceInt = uint4( 16777216.0 * Radiance );
	InterlockedAdd( shSumRadianceInt.x, RadianceInt.x );
	InterlockedAdd( shSumRadianceInt.y, RadianceInt.y );
	InterlockedAdd( shSumRadianceInt.z, RadianceInt.z );
	InterlockedAdd( shSumRadianceInt.w, RadianceInt.w );

	// Store result
	GroupMemoryBarrierWithGroupSync();
	float4	SumRadiance = shSumRadianceInt / 16777216.0;

	if ( _GroupThreadID.x == 0 )
	{
		_Output[TexelIndex].Irradiance = SumRadiance;
//		_Output[TexelIndex].Irradiance = float4( 1, 0, 0, 0 );
		_AccumOutput[TexelIndex].Irradiance = SumRadiance;
	}
}


//////////////////////////////////////////////////////////////////////////
// Indirect lighting samples the room
// Each thread casts a single ray toward the room and gathers existing lighting
//
Ray	GenerateRayIndirect( uint _TexelIndex, uint _TexelGroup, uint _RayIndex, uint _RaysCount, inout uint4 _Seed )
{
	LightMapInfos	Source = _Input[_TexelIndex];

	float3	Direction = CosineSampleHemisphere( Random2( _Seed ) );

// float2	Test = float2( Random1( _Seed ), 0.1 );
// float3	Direction = CosineSampleHemisphere( Test );

	Ray	Result;
		Result.P = Source.Position + 1e-3 * Source.Normal;	// Offset just a chouia
		Result.V = Direction.x * Source.Tangent + Direction.y * Source.BiTangent + Direction.z * Source.Normal;

//Result.V = Source.Normal;//###
//Result.V = normalize( -1.0.xxx );

	return Result;
}

float4	SampleIrradiance( StructuredBuffer<LightMapResult> _PreviousPass, float2 _UV, uint2 _LightMapSize )
{
	float2	UV = _UV * _LightMapSize;
	uint2	IntUV0 = uint2( floor( UV ) );
	float2	uv = UV - IntUV0;
	uint2	IntUV1 = min( IntUV0+1, _LightMapSize-1 );
			IntUV0 = min( IntUV0, _LightMapSize-1 );

	float4	I00 = _PreviousPass[_LightMapSize.x*IntUV0.y+IntUV0.x].Irradiance;
	float4	I01 = _PreviousPass[_LightMapSize.x*IntUV0.y+IntUV1.x].Irradiance;
	float4	I10 = _PreviousPass[_LightMapSize.x*IntUV1.y+IntUV0.x].Irradiance;
	float4	I11 = _PreviousPass[_LightMapSize.x*IntUV1.y+IntUV1.x].Irradiance;

	float4	I0 = lerp( I00, I01, uv.x );
	float4	I1 = lerp( I10, I11, uv.x );
	return lerp( I0, I1, uv.y );
}

[numthreads( 1024, 1, 1 )]
void	CS_Indirect(	uint3 _GroupID			: SV_GroupID,			// Defines the group offset within a Dispatch call, per dimension of the dispatch call
						uint3 _ThreadID			: SV_DispatchThreadID,	// Defines the global thread offset within the Dispatch call, per dimension of the group
						uint3 _GroupThreadID	: SV_GroupThreadID,		// Defines the thread offset within the group, per dimension of the group
						uint  _GroupIndex		: SV_GroupIndex )		// Provides a flattened index for a given thread within a given group
{
	shSumRadianceInt = 0;
 	GroupMemoryBarrierWithGroupSync();

	uint	TexelIndex, TexelGroup, RayIndex, RaysCount;
	ComputeTexelRayInfos( _GroupID.xy, _GroupIndex.x, GROUPS_PER_TEXEL_INDIRECT, TexelIndex, TexelGroup, RayIndex, RaysCount );

	uint4	Seed = BuildSeed( TexelIndex, _Input[TexelIndex] );

	// Generate the 4 rays
	Ray		R = GenerateRayIndirect( TexelIndex, TexelGroup, RayIndex, RaysCount, Seed );

	// Compute radiance coming from the walls
	Intersection	I;
	float			ClosestHitDistance = INFINITY;
	float4			Radiance = 0.0;

	// Test lights first
// 	ClosestHitDistance = min( ClosestHitDistance, IntersectRectangle( R, I, LIGHT_POS0, LIGHT_NORMAL, float3( LIGHT_SIZE.x, 0, 0 ), float3( 0, 0, LIGHT_SIZE.y ), -1 ) );
// 	ClosestHitDistance = min( ClosestHitDistance, IntersectRectangle( R, I, LIGHT_POS1, LIGHT_NORMAL, float3( LIGHT_SIZE.x, 0, 0 ), float3( 0, 0, LIGHT_SIZE.y ), -1 ) );
// 	ClosestHitDistance = min( ClosestHitDistance, IntersectRectangle( R, I, LIGHT_POS2, LIGHT_NORMAL, float3( LIGHT_SIZE.x, 0, 0 ), float3( 0, 0, LIGHT_SIZE.y ), -1 ) );
// 	ClosestHitDistance = min( ClosestHitDistance, IntersectRectangle( R, I, LIGHT_POS3, LIGHT_NORMAL, float3( LIGHT_SIZE.x, 0, 0 ), float3( 0, 0, LIGHT_SIZE.y ), -1 ) );

I.Distance = INFINITY;
I.Position = I.Normal = I.Tangent = I.BiTangent = 0.0;
I.UV = 0.0;
I.MaterialID = 123456;

//	if ( ClosestHitDistance >= INFINITY )
	{	// This means we didn't hit a light
		// We can safely assume we're hitting a wall
		ClosestHitDistance = IntersectAABoxIn( R, I, ROOM_POSITION, ROOM_INV_HALF_SIZE, 0 );

		// Retrieve irradiance from the previous pass
		float4	SourceIrradiance = 0.0;
		uint2	LightMapHalfSize = uint2( _LightMapSize.x, _LightMapSize.x/2 );
		switch ( I.MaterialID )
		{
		case 0: SourceIrradiance = WALL_REFLECTANCE0 * SampleIrradiance( _PreviousPass0, I.UV, _LightMapSize.xx ); break;	// Top
		case 1: SourceIrradiance = WALL_REFLECTANCE1 * SampleIrradiance( _PreviousPass1, I.UV, _LightMapSize.xx ); break;	// Bottom
		case 2: SourceIrradiance = WALL_REFLECTANCE2 * SampleIrradiance( _PreviousPass2, I.UV, LightMapHalfSize ); break;	// Left
		case 3: SourceIrradiance = WALL_REFLECTANCE3 * SampleIrradiance( _PreviousPass3, I.UV, LightMapHalfSize ); break;	// Right
		case 4: SourceIrradiance = WALL_REFLECTANCE4 * SampleIrradiance( _PreviousPass4, I.UV, LightMapHalfSize ); break;	// Back
		case 5: SourceIrradiance = WALL_REFLECTANCE5 * SampleIrradiance( _PreviousPass5, I.UV, LightMapHalfSize ); break;	// Front
		}

		// Convert into radiance
		Radiance = SourceIrradiance * IRRADIANCE_WEIGHT_INDIRECT * RECITWOPI;

//Radiance = SourceIrradiance;
//Radiance = abs(SampleIrradiance( _PreviousPass5, I.UV, _LightMapSize.xx ).yzwx);
//Radiance = _PreviousPass5[_LightMapSize.x * uint(I.UV.y * _LightMapSize.x) + uint(I.UV.x * _LightMapSize.x)].Irradiance.xyzw;

// Radiance = float4( abs( R.V ), 0 );
// Radiance = float4( R.P, 0 );
//Radiance = I.MaterialID;
//Radiance = 0.0004 * I.Distance;
	}

	// Accumulate
	uint4	RadianceInt = uint4( 16777216.0 * Radiance );
	InterlockedAdd( shSumRadianceInt.x, RadianceInt.x );
	InterlockedAdd( shSumRadianceInt.y, RadianceInt.y );
	InterlockedAdd( shSumRadianceInt.z, RadianceInt.z );
	InterlockedAdd( shSumRadianceInt.w, RadianceInt.w );

	// Store result
	GroupMemoryBarrierWithGroupSync();
	float4	SumRadiance = shSumRadianceInt / 16777216.0;

	if ( _GroupThreadID.x == 0 )
	{
		_Output[TexelIndex].Irradiance = SumRadiance;
		_AccumOutput[TexelIndex].Irradiance += SumRadiance;
//		_AccumOutput[TexelIndex].Irradiance = Radiance;
//		_AccumOutput[TexelIndex].Irradiance = I.Distance;
//		_AccumOutput[TexelIndex].Irradiance = float4( I.UV, 0, 0 );
//		_AccumOutput[TexelIndex].Irradiance = float4( I.Position, 0 );
//		_AccumOutput[TexelIndex].Irradiance = float4( R.P, 0 );
//		_AccumOutput[TexelIndex].Irradiance = float4( R.V, 0 );
//		_AccumOutput[TexelIndex].Irradiance = float4( 1, 0, 0, 1 );
//		_AccumOutput[TexelIndex].Irradiance = I.MaterialID;
	}
}

