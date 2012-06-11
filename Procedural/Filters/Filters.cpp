#include "../../GodComplex.h"

//////////////////////////////////////////////////////////////////////////
// Gaussian Blur
struct __BlurStruct
{
	TextureBuilder*	pSource;
	int		W, H;
	int		Size;
	float*	pWeights;
	float	InvSumWeights;
};

// Wrap versions
void	FillBlurGaussianHW( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__BlurStruct&	Data = *((__BlurStruct*) _pData);

	float	Xl = _X-1.0f, Xr = _X+1.0f;
	float	Y = float(_Y);

	NjFloat4	SumColors;
	Data.pSource->SampleWrap( float(_X), Y, SumColors );

	NjFloat4	Temp;
	for ( int i=0; i < Data.Size; i++ )
	{
		float	Weight = Data.pWeights[i];

		// Accumulate from the left
		Data.pSource->SampleWrap( Xl, Y, Temp );	Xl--;
		SumColors = SumColors + Weight * Temp;

		// Accumulate from the right
		Data.pSource->SampleWrap( Xr, Y, Temp );	Xr++;
		SumColors = SumColors + Weight * Temp;
	}

	// Normalize result
	_Color = Data.InvSumWeights * SumColors;
}
void	FillBlurGaussianVW( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__BlurStruct&	Data = *((__BlurStruct*) _pData);

	float	X = float(_X);
	float	Yl = _Y-1.0f, Yr = _Y+1.0f;

	NjFloat4	SumColors;
	Data.pSource->SampleWrap( X, float(_Y), SumColors );

	NjFloat4	Temp;
	for ( int i=0; i < Data.Size; i++ )
	{
		float	Weight = Data.pWeights[i];

		// Accumulate from the top
		Data.pSource->SampleWrap( X, Yl, Temp );	Yl--;
		SumColors = SumColors + Weight * Temp;

		// Accumulate from the bottom
		Data.pSource->SampleWrap( X, Yr, Temp );	Yr++;
		SumColors = SumColors + Weight * Temp;
	}

	// Normalize result
	_Color = Data.InvSumWeights * SumColors;
}
// Clamp versions
void	FillBlurGaussianHC( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__BlurStruct&	Data = *((__BlurStruct*) _pData);

	float	Xl = _X-1.0f, Xr = _X+1.0f;
	float	Y = float(_Y);

	NjFloat4	SumColors;
	Data.pSource->SampleClamp( Xl, Y, SumColors );

	NjFloat4	Temp;
	for ( int i=0; i < Data.Size; i++ )
	{
		float	Weight = Data.pWeights[i];

		// Accumulate from the left
		Data.pSource->SampleClamp( Xl, Y, Temp );	Xl--;
		SumColors = SumColors + Weight * Temp;

		// Accumulate from the right
		Data.pSource->SampleClamp( Xr, Y, Temp );	Xr++;
		SumColors = SumColors + Weight * Temp;
	}

	// Normalize result
	_Color = Data.InvSumWeights * SumColors;
}
void	FillBlurGaussianVC( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__BlurStruct&	Data = *((__BlurStruct*) _pData);

	float	X = float(_X);
	float	Yl = _Y-1.0f, Yr = _Y+1.0f;

	NjFloat4	SumColors;
	Data.pSource->SampleClamp( X, float(_Y), SumColors );

	NjFloat4	Temp;
	for ( int i=0; i < Data.Size; i++ )
	{
		float	Weight = Data.pWeights[i];

		// Accumulate from the top
		Data.pSource->SampleClamp( X, Yl, Temp );	Yl--;
		SumColors = SumColors + Weight * Temp;

		// Accumulate from the bottom
		Data.pSource->SampleClamp( X, Yr, Temp );	Yr++;
		SumColors = SumColors + Weight * Temp;
	}

	// Normalize result
	_Color = Data.InvSumWeights * SumColors;
}

void	Filters::BlurGaussian( TextureBuilder& _Builder, float _SizeX, float _SizeY, bool _bWrap, float _MinWeight )
{
	int	W = _Builder.GetWidth(), H = _Builder.GetHeight();

	TextureBuilder	Temp( W, H );

	// Apply horizontal pass
	{
		__BlurStruct	BS;
		BS.pSource = &_Builder;
		BS.W = W;
		BS.H = H;

		BS.Size = ceilf( _SizeX );
		float	k = logf( _MinWeight ) / (_SizeX*_SizeX);

		BS.pWeights = new float[BS.Size];
		BS.InvSumWeights = 1.0f;
		for ( int i=0; i < BS.Size; i++ )
		{
			BS.pWeights[i] = expf( k * (1+i)*(1+i) );
			BS.InvSumWeights += 2.0f * BS.pWeights[i];
		}
		BS.InvSumWeights = 1.0f / BS.InvSumWeights;

		Temp.Fill( _bWrap ? FillBlurGaussianHW : FillBlurGaussianHC, &BS );

		delete[] BS.pWeights;
	}

	// Apply vertical pass
	{
		__BlurStruct	BS;
		BS.pSource = &Temp;
		BS.W = W;
		BS.H = H;

		BS.Size = ceilf( _SizeY );
		float	k = logf( _MinWeight ) / (_SizeY*_SizeY);

		BS.pWeights = new float[BS.Size];
		BS.InvSumWeights = 1.0f;
		for ( int i=0; i < BS.Size; i++ )
		{
			BS.pWeights[i] = expf( k * (1+i)*(1+i) );
			BS.InvSumWeights += 2.0f * BS.pWeights[i];
		}
		BS.InvSumWeights = 1.0f / BS.InvSumWeights;

		_Builder.Fill( _bWrap ? FillBlurGaussianVW : FillBlurGaussianVC, &BS );

		delete[] BS.pWeights;
	}
}

//////////////////////////////////////////////////////////////////////////
// Unsharp masking
void	FillUnsharpMaskSubtract( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	TextureBuilder&	SourceSmooth = *((TextureBuilder*) _pData);

	NjFloat4	Smooth;
	SourceSmooth.Get( _X, _Y, Smooth );

	_Color = 2.0f * _Color - Smooth;
	_Color = _Color.Max( NjFloat4::Zero );	// Clip negatives
}

void	Filters::UnsharpMask( TextureBuilder& _Builder, float _Size )
{
	// Blur the source
	TextureBuilder	Temp( _Builder.GetWidth(), _Builder.GetHeight() );
	Temp.CopyFrom( _Builder );
	BlurGaussian( Temp, _Size, _Size );

	// Subtract
	_Builder.Fill( FillUnsharpMaskSubtract, &Temp );
}

//////////////////////////////////////////////////////////////////////////
// Luminance tweaking
struct __BCGStruct
{
	float	B, C, G;
};
void	FillBCG( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__BCGStruct&	BCG = *((__BCGStruct*) _pData);

	float	Luma = _Color | LUMINANCE;
//	float	ContrastedLuma = BCG.B + BCG.C * (Luma - 0.5f);
	float	ContrastedLuma = 0.5f + BCG.C * (Luma + BCG.B);
			ContrastedLuma = SATURATE( ContrastedLuma );
	float	NewLuma = powf( ContrastedLuma, BCG.G );

	_Color = _Color * (NewLuma / Luma);
}

void	Filters::BrightnessContrastGamma( TextureBuilder& _Builder, float _Brightness, float _Contrast, float _Gamma )
{
	__BCGStruct	BCG;
//	BCG.B = 0.5f + _Brightness;
	BCG.B = _Brightness - 0.5f;
	BCG.C = tanf( HALFPI * 0.5f * (1.0f + _Contrast) );
	BCG.G = _Gamma;

	_Builder.Fill( FillBCG, &BCG );
}

//////////////////////////////////////////////////////////////////////////
// Filters
struct __EmbossStruct
{
	TextureBuilder*	pSource;
	NjFloat2		Direction;
	float			Amplitude;
};
void	FillEmboss( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__EmbossStruct&	Params = *((__EmbossStruct*) _pData);

	NjFloat4	C0, C1;
	Params.pSource->SampleWrap( _X + Params.Direction.x, _Y + Params.Direction.y, C0 );
	Params.pSource->SampleWrap( _X - Params.Direction.x, _Y - Params.Direction.y, C1 );

	_Color = 0.5f * NjFloat4::One + Params.Amplitude * (C0 - C1);
}

void	Filters::Emboss( TextureBuilder& _Builder, const NjFloat2& _Direction, float _Amplitude )
{
	TextureBuilder	Temp( _Builder.GetWidth(), _Builder.GetHeight() );
	Temp.CopyFrom( _Builder );

	__EmbossStruct	Params;
	Params.pSource = &Temp;
	Params.Direction = _Direction;
	Params.Direction.Normalize();
	Params.Amplitude = _Amplitude;

	_Builder.Fill( FillEmboss, &Params );
}


//////////////////////////////////////////////////////////////////////////
// Erosion
struct __ErosionStruct
{
	NjFloat4*	pSource;
	int			W, H;
	int			Size;
};
void	FillErode( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__ErosionStruct&	Params = *((__ErosionStruct*) _pData);

	NjFloat4	C;
	_Color = FLOAT32_MAX * NjFloat4::One;
	for ( int Y=_Y-Params.Size; Y <= _Y+Params.Size; Y++ )
	{
		int			SampleY = ((Params.H+Y) % Params.H);
		NjFloat4*	pScanline = &Params.pSource[Params.W * SampleY];
		for ( int X=_X-Params.Size; X <= _X+Params.Size; X++ )
		{
			int	SampleX = (Params.W+X) % Params.W;
			_Color = _Color.Min( pScanline[SampleX] );
		}
	}
}

void	Filters::Erode( TextureBuilder& _Builder, int _KernelSize )
{
	TextureBuilder	Temp( _Builder.GetWidth(), _Builder.GetHeight() );
	Temp.CopyFrom( _Builder );

	__ErosionStruct	Params;
	Params.pSource = Temp.GetMips()[0];
	Params.W = Temp.GetWidth();
	Params.H = Temp.GetHeight();
	Params.Size = _KernelSize;

	_Builder.Fill( FillErode, &Params );
}


//////////////////////////////////////////////////////////////////////////
// Dilation
struct __DilationStruct
{
	NjFloat4*	pSource;
	int			W, H;
	int			Size;
};
void	FillDilate( int _X, int _Y, const NjFloat2& _UV, NjFloat4& _Color, void* _pData )
{
	__DilationStruct&	Params = *((__DilationStruct*) _pData);

	NjFloat4	C;
	_Color = -FLOAT32_MAX * NjFloat4::One;
	for ( int Y=_Y-Params.Size; Y <= _Y+Params.Size; Y++ )
	{
		int			SampleY = ((Params.H+Y) % Params.H);
		NjFloat4*	pScanline = &Params.pSource[Params.W * SampleY];
		for ( int X=_X-Params.Size; X <= _X+Params.Size; X++ )
		{
			int	SampleX = (Params.W+X) % Params.W;
			_Color = _Color.Max( pScanline[SampleX] );
		}
	}
}

void	Filters::Dilate( TextureBuilder& _Builder, int _KernelSize )
{
	TextureBuilder	Temp( _Builder.GetWidth(), _Builder.GetHeight() );
	Temp.CopyFrom( _Builder );

	__DilationStruct	Params;
	Params.pSource = Temp.GetMips()[0];
	Params.W = Temp.GetWidth();
	Params.H = Temp.GetHeight();
	Params.Size = _KernelSize;

	_Builder.Fill( FillDilate, &Params );
}
