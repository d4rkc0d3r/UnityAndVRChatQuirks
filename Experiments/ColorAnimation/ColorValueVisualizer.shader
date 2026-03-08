Shader "d4rkpl4y3r/Debug/Color Value Visualizer"
{
	Properties
	{
		[IntRange]_AASampleCount("AA Sample Count", Range(1, 128)) = 8
		_AARadius("AA Radius", Float) = 0.6
		_AAPower("AA Power", Range(0.1, 2)) = 0.5
		[ToggleUI]_AngleOffset("Angle Jitter", Float) = 0
		[ToggleUI]_RadiusOffset("Radius Offset", Float) = 0
		_ColorLDRrgba("Color LDR rgba", Color) = (0.5, 0.5, 0.5, 1)
		[HDR]_ColorHDRrgba("Color HDR rgba", Color) = (0.5, 0.5, 0.5, 1)
		_ColorLDRxyzw("Color LDR xyzw", Color) = (0.5, 0.5, 0.5, 1)
		[HDR]_ColorHDRxyzw("Color HDR xyzw", Color) = (0.5, 0.5, 0.5, 1)
	}
	SubShader
	{
		Pass
		{
			CGPROGRAM
			#pragma vertex empty
			#pragma geometry geom
			#pragma fragment frag
			#pragma target 5.0

			#include "UnityCG.cginc"

			float _AASampleCount;
			float _AARadius;
			float _AAPower;
			float _AngleOffset;
			float _RadiusOffset;
			float4 _ColorLDRrgba;
			float4 _ColorHDRrgba;
			float4 _ColorLDRxyzw;
			float4 _ColorHDRxyzw;

			float _VRChatMirrorMode;
			float3 _VRChatMirrorCameraPos;

			#define MAX_CHARACTERS 20

			struct v2f
			{
				float4 pos : SV_Position;
				float2 uv : TEXCOORD0;
				nointerpolation uint characterCount : CHARACTER_COUNT;
				nointerpolation bool reverse : REVERSE;
				nointerpolation uint characters[MAX_CHARACTERS] : CHARACTERS;
			};
			
			void empty() {}
			
			static const uint charLookup[20] = {
				0x75557, // 0
				0x22222, // 1
				0x74717, // 2
				0x74747, // 3
				0x55744, // 4
				0x71747, // 5
				0x71757, // 6
				0x74444, // 7
				0x75757, // 8
				0x75747, // 9
				0x75755, // A
				0x35353, // B
				0x71117, // C
				0x35553, // D
				0x71317, // E
				0x71311, // F
				0x00002, // .
				0x00700, // -
				0x00525, // x
				0x00000  // empty
			};

			static const int CHAR_DOT = 16;
			static const int CHAR_MINUS = 17;
			static const int CHAR_X = 18;
			static const int CHAR_EMPTY = 19;

			v2f uintBaseSixteen(uint number)
			{
				v2f o = (v2f)0;
				[unroll]
				for (int i = 0; i < 8; i++)
				{
					o.characters[9 - i] = (number >> (i * 4)) & 0xF;
				}
				o.characters[1] = CHAR_X;
				o.characters[0] = 0;
				o.characterCount = 10;
				return o;
			}

			v2f intBaseTen(int number)
			{
				v2f o = (v2f)0;
				uint absNumber = abs(number);
				uint highestNonZeroDigit = 0;
				[unroll]
				for (int i = 0; i < 10; i++)
				{
					uint factor = round(pow(10, i));
					uint digit = (absNumber / factor) % 10;
					if (digit != 0)
					{
						highestNonZeroDigit = i;
					}
					o.characters[i] = digit;
				}
				[unroll]
				for (uint k = 0; k < 11; k++)
				{
					if (k > highestNonZeroDigit)
					{
						o.characters[k] = CHAR_EMPTY;
					}
					if (k == highestNonZeroDigit + 1 && number < 0)
					{
						o.characters[k] = CHAR_MINUS;
					}
				}
				o.characterCount = highestNonZeroDigit + 1 + (number < 0);
				o.reverse = true;
				return o;
			}

			v2f floatBaseTenScientific(float number)
			{
				v2f o = (v2f)0;
				int exponent = floor(log10(abs(number)));
				float mantissa = abs(number) / pow(10, exponent);
				float mantissaIndex = 0;
				float exponentIndex = 0;
				bool hasExponent = false;
				bool hasExponentSign = false;
				[unroll]
				for (int i = 0; i < 13; i++)
				{
					if (i == 0)
					{
						o.characters[i] = number < 0 ? CHAR_MINUS : CHAR_EMPTY;
					}
					else if (i == 2)
					{
						o.characters[i] = CHAR_DOT;
					}
					else if (mantissaIndex < 7)
					{
						uint digit = floor(mantissa);
						o.characters[i] = digit;
						mantissa = (mantissa - digit) * 10;
						mantissaIndex++;
					}
					else if (!hasExponent)
					{
						o.characters[i] = 0xE;
						hasExponent = true;
					}
					else if (!hasExponentSign)
					{
						o.characters[i] = exponent < 0 ? CHAR_MINUS : CHAR_EMPTY;
						hasExponentSign = true;
					}
					else if (exponentIndex < 2)
					{
						uint digit = abs(exponent) / round(pow(10, 1 - exponentIndex)) % 10;
						o.characters[i] = digit;
						exponentIndex++;
					}
					else
					{
						o.characters[i] = CHAR_EMPTY;
					}
				}
				o.characterCount = 13;
				return o;
			}

			v2f floatBaseTen(float number)
			{
				v2f o = (v2f)0;
				int digitsBeforeDot = floor(max(0, log10(abs(number))));
				int digitsAfterDot = max(1, 7 - digitsBeforeDot);
				if (abs(number) < 1)
				{
					digitsBeforeDot = 0;
					digitsAfterDot = 7 + ceil(-log10(abs(number)));
				}
				int digitToDo = digitsBeforeDot + digitsAfterDot;
				float currentWorkingNumber = abs(number) / pow(10, digitsBeforeDot);
				[unroll]
				for (int i = 0; i < 13; i++)
				{
					if (i == 0 && number < 0)
					{
						o.characters[i] = CHAR_MINUS;
					}
					else if (i == (1 + digitsBeforeDot + (number < 0)))
					{
						o.characters[i] = CHAR_DOT;
					}
					else if (digitToDo > 0)
					{
						uint digit = floor(currentWorkingNumber);
						o.characters[i] = digit;
						currentWorkingNumber = (currentWorkingNumber - digit) * 10;
						digitToDo--;
					}
					else
					{
						o.characters[i] = CHAR_EMPTY;
					}
				}
				o.characterCount = (number < 0) + digitsBeforeDot + 1 + digitsAfterDot;
				return o;
			}

			v2f floatBaseTenAuto(float number)
			{
				if ((abs(number) <= 1e-4 || abs(number) >= 1e6) && number != 0)
				{
					return floatBaseTenScientific(number);
				}
				else if (frac(number) == 0)
				{
					return intBaseTen(number);
				}
				else 
				{
					return floatBaseTen(number);
				}
			}

			#define COUNT 8

			[maxvertexcount(4)]
			[instance(COUNT)]
			void geom(point float4 input[1] : POSITION, inout TriangleStream<v2f> tristream, uint triID : SV_PrimitiveID, uint instID : SV_GSInstanceID)
			{
				if (triID > 0)
					return;

				v2f o = (v2f)0;

				float2 numbersToVisualize[COUNT] = {
					_ColorLDRrgba.r, 0,
					_ColorLDRrgba.r, 1,
					_ColorHDRrgba.r, 0,
					_ColorHDRrgba.r, 1,
					_ColorLDRxyzw.x, 0,
					_ColorLDRxyzw.x, 1,
					_ColorHDRxyzw.x, 0,
					_ColorHDRxyzw.x, 1
				};

				float2 numberToVisualize = numbersToVisualize[instID];

				if (numberToVisualize.y == 0)
					o = floatBaseTenAuto(numberToVisualize.x);
				else
					o = uintBaseSixteen(asuint(numberToVisualize.x));

				float objectScale = length(unity_ObjectToWorld._11_12_13) * 0.1;
				float3 pos = unity_ObjectToWorld._14_24_34;
				pos.y += objectScale * (-1.0 + COUNT - 2.0 * instID);
				float3 cameraPos = _VRChatMirrorMode ? _VRChatMirrorCameraPos : UNITY_MATRIX_I_V._14_24_34;
				#if defined(USING_STEREO_MATRICES)
					cameraPos = unity_StereoWorldSpaceCameraPos[0] * 0.5 + unity_StereoWorldSpaceCameraPos[1] * 0.5;
				#endif
				float3 camToQuad = UNITY_MATRIX_P._43 == 0
					? -UNITY_MATRIX_I_V._13_23_33
					: pos - cameraPos;

				float3 zaxis = normalize(camToQuad);
				float3 xaxis = normalize(float3(zaxis.z, 0, -zaxis.x));
				float3 yaxis = cross(zaxis, xaxis);

				const float2 offsets[4] = { float2(1, 1), float2(1, -1), float2(-1, 1), float2(-1, -1) };
				[unroll]
				for (int i = 0; i < 4; i++)
				{
					o.pos = UnityWorldToClipPos(pos + xaxis * ((o.characterCount * 4 + 1) / 7.0 * objectScale * offsets[i].x) + yaxis * (objectScale * offsets[i].y));
					o.uv = offsets[i] * 0.5 + 0.5;
					if (_VRChatMirrorMode)
						o.uv.x = 1 - o.uv.x;
					tristream.Append(o);
				}
			}

			float4 color(v2f input)
			{
				float2 scaledUV;
				scaledUV.x = input.uv.x * (input.characterCount * 4 + 1);
				scaledUV.y = input.uv.y * 7;
				float charIndex = floor(scaledUV.x / 4);
				if (input.reverse)
				{
					charIndex = input.characterCount - 1 - charIndex;
				}
				uint charLookupIndex = (charIndex < (float)input.characterCount && charIndex >= 0) ? input.characters[int(charIndex)] : CHAR_EMPTY;
				float2 digitUV = floor(float2(frac(scaledUV.x / 4) * 4, scaledUV.y)) - 1;
				int bitIndex = int(digitUV.y) * 4 + int(digitUV.x);
				bool bit = (charLookup[charLookupIndex] & (1 << bitIndex)) != 0;
				return bit && all(digitUV == clamp(digitUV, 0, float2(2,4))) ? float4(1, 1, 1, 1) : float4(0, 0, 0, 1);
			}

			uint murmur3(uint x)
			{
				x ^= x >> 16;
				x *= 0x85ebca6b;
				x ^= x >> 13;
				x *= 0xc2b2ae35;
				x ^= x >> 16;
				return x;
			}

			float4 frag(v2f input) : SV_Target
			{
				float inverseGoldenRatio = 0.61803398;
				float angleOffset = _AngleOffset * UNITY_TWO_PI * (murmur3((uint)input.pos.y ^ murmur3((uint)input.pos.x)) / exp2(32));
				float4 sum = 0;
				for (float i = 0; i < _AASampleCount; i++)
				{
					float angle = i * (inverseGoldenRatio * UNITY_TWO_PI) + angleOffset;
					float2 offset = (float2(cos(angle), sin(angle)) * pow((i + 0.5 * (_AASampleCount > 1 && _RadiusOffset > 0.5)) / _AASampleCount, _AAPower)) * _AARadius;
					v2f offsetInput = input;
					offsetInput.uv += offset.x * ddx(input.uv) + offset.y * ddy(input.uv);
					sum += color(offsetInput);
				}
				return sum / _AASampleCount;
			}
			ENDCG
		}
	}
}
