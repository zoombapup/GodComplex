#pragma once

#ifndef RENDERER_H_INCLUDED
#define RENDERER_H_INCLUDED

#include "targetver.h"

#define WIN32_LEAN_AND_MEAN			 // Exclude rarely-used stuff from Windows headers

// #include "C:\Program Files (x86)\Microsoft DirectX SDK (June 2010)\Include\d3d11.h"
// #include "C:\Program Files (x86)\Microsoft DirectX SDK (June 2010)\Include\dxgi.h"
#include "d3d11.h"
#include "dxgi.h"

#ifdef _DEBUG
#include <assert.h>
#define ASSERT( condition ) assert( condition )
#else
#define ASSERT( condition )
#endif

#define NUAJ_LIB
#include "../NuajAPI/API/Types.h"
#include "../NuajAPI/Math/Math.h"

#endif