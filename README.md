# UnityAndVRChatQuirks
A loose collection of random small mostly shader related things I stumbled upon.

## Differences between AMD and Nvidia
### Alpha to Coverage
AMD do apply screen space dithering when using alpha to coverage while nvidia does not. Use `SV_Coverage` to write to the coverage mask directly if you desire the same behavior across both vendors. `GetRenderTargetSampleCount()` can be used to get the current MSAA sample count to set the mask like so:
```c
float scaledAlpha = saturate(alpha) * GetRenderTargetSampleCount() + 0.5;
covMask = (1u << ((uint)(scaledAlpha))) - 1u;
```
### Point Filtering on Float Textures
AMD does flush denormals to zero when sampling float textures with point filtering while nvidia does not.  
Use the `Texture2D.Load` function when you need exact bit values from float textures.
