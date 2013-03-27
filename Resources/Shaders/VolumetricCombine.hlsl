//////////////////////////////////////////////////////////////////////////
// This shader finally combines the volumetric rendering with the actual screen
//
#include "Inc/Global.hlsl"
#include "Inc/Volumetric.hlsl"

Texture2D		_TexDebug0	: register(t10);
Texture2D		_TexDebug1	: register(t11);
Texture2DArray	_TexDebug2	: register(t12);

//[
cbuffer	cbObject	: register( b10 )
{
	float3		_dUV;
};
//]

struct	VS_IN
{
	float4	__Position	: SV_POSITION;
};

VS_IN	VS( VS_IN _In )	{ return _In; }

float4	PS( VS_IN _In ) : SV_TARGET0
{
	float2	UV = _In.__Position.xy * _dUV.xy;
//return float4( UV, 0, 1 );
	
// 	float2	Depth = _TexDebug1.SampleLevel( LinearClamp, UV, 0.0 ).xy;
// return 0.5 * Depth.y;
// return 0.5 * (Depth.y - Depth.x);

//	float3	BackgroundColor = 0.9 * float3( 135, 206, 235 ) / 255.0;
//	float3	BackgroundColor = 0.3;


	// From iQ's clouds
//    vec4 res = raymarch( ro, View );

	float3	View = normalize( float3( _CameraData.x * (2.0 * UV.x - 1.0), -_CameraData.y * (2.0 * UV.y - 1.0), 1.0 ) );
			View = mul( float4( View, 0.0 ), _Camera2World ).xyz;
	float	Sun = saturate( dot( _LightDirection, View ) );
	float3	BackgroundColor = float3( 0.6, 0.71, 0.75 ) - View.y * 0.2 * float3( 1.0, 0.9, 1.0 ) + 0.15*0.5;	// Sky gradient
//			BackgroundColor += 0.8 * float3(1.0,0.8,0.6) * pow( Sun, 8.0 );	// Sun glow
			BackgroundColor *= 0.95;
//		 	BackgroundColor += 0.2 * float3(1.0,0.95,0.8) * pow( Sun, 3.0 );

	float4	ScatteringExtinction = _TexDebug0.SampleLevel( LinearClamp, UV, 0.0 );
return float4( BackgroundColor * ScatteringExtinction.w + ScatteringExtinction.xyz, 1.0 );

	float4	C0 = _TexDebug2.SampleLevel( LinearClamp, float3( UV, 0 ), 0.0 );
	float4	C1 = _TexDebug2.SampleLevel( LinearClamp, float3( UV, 1 ), 0.0 );
return 1.0 * C0;
return 1.0 * abs( C0.x );
return 4.0 * abs(C0);

//return fmod( 0.5 * _Time.x, 1.0 );

	float3	ShadowPos = float3( 2.0 * fmod( 0.5 * _Time.x, 1.0 ) - 1.0, 1.0 - 2.0 * UV.y, _ShadowZMax.x * UV.x );
	return 0.999 * GetTransmittance( ShadowPos );
}
