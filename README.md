# UnityAndVRChatQuirks
A loose collection of random small mostly shader related things I stumbled upon.

## Differences between AMD and Nvidia
### Alpha to Coverage
AMD does apply screen space dithering when using alpha to coverage while nvidia does not. Use `SV_Coverage` to write to the coverage mask directly if you desire the same behavior across both vendors. `GetRenderTargetSampleCount()` can be used to get the current MSAA sample count to set the mask like so:
```c
float scaledAlpha = saturate(alpha) * GetRenderTargetSampleCount() + 0.5;
covMask = (1u << ((uint)(scaledAlpha))) - 1u;
```
### Point Filtering on Float Textures
AMD does flush denormals to zero when sampling float textures with point filtering while nvidia does not.  
Use the `Texture2D.Load` function when you need exact bit values from float textures.

### Transcendental Functions
Transcendental functions like `sin()`, `cos()`, `exp2()`, `log2()`, `rsqrt()` & `rcp()` have relaxed precision requirements and as such the vendors do give slightly different results for them. Don't do rng based on aliasing of sin with big values for example as that can amplify those differences to give very different results on different hardware.

### Tessellation Patch Size Miss Match
When declaring a hull shader with a patch size that is different from the per primitive vertex count in the mesh, AMD and Nvidia behave differently. Nvidia will use the mesh declared vertex per primitive count while AMD will use the hull shader declared patch size. For example if you do quad tess on a point mesh with 4 control points per patch on AMD you will get 1/4 the patches vs the primitive count of the mesh while on nvidia you will get 1:1 patch to primitive count.

## Differences between Shader Constant Folding and Runtime Evaluation
There are some differences between how certain functions are evaluated at compile time (constant folding) and at runtime in shaders. This can lead to unexpected results when using "Shader lock in" features like many VRChat shaders and my optimizer with "Write Properties as Static Values" do.
### round()
`round()` is round to nearest even at runtime but constant folding in fxc treats it as round to nearest up.  
`round(0.5)` results in `1` if the 0.5 is known at compile time but `0` at runtime.
### smoothstep()
`smoothstep(a, a, a)` evaluates to `0` at runtime but is a toss up between `0` and `1` during constant folding depending on which of the parameters are known at compile time.
### pow()
`pow(x, p)` gets compiled to `exp2(p * log2(x))` at runtime. This means it is `NaN` for negative `x` values.
* If `p` & `x` are known at compile time and `p` is an integer value, negative `x` values are not `NaN`.  
* If `p` is known at compile time and is of value `2`, `3`, `4`, `5`, `6` or `8`, it will get compiled as a series of mul and adds. This also means negative `x` values are not `NaN`.
* `pow(0, 0)` is `NaN` at runtime, `1` if `p` is known at compile time and then `0` if only `x` but not `p` is known at compile time.
### sampler reuse
When reusing sampler states across multiple textures you have to make sure to "use" its source texture in the shader that can't be constant folded away. Otherwise the sampler state will also get removed during constant folding leading to a compile error. A good way to hide something from constant folding is to use a dummy constant buffer variable in a branch. The variable will be 0 if not set from the properties block or a global property setter but the compiler doesn't know its 0 at compile time.
### Transcendental Functions
Just like with different GPU vendors or even generations, transcendental functions can give different results when constant folded vs runtime evaluation.
