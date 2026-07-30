# UnityAndVRChatQuirks
A loose collection of random small mostly shader related things I stumbled upon.  
Most of these are extremely niche and or cursed edge cases.  
This simply represents what I have learned over the years and is only relevant to unity dx11 with fxc. There could be misunderstandings about these systems on my part as well as there is not much prior information to easily find about these topics.

## Differences between AMD and Nvidia
### Alpha to Coverage
AMD does apply screen space dithering when using alpha to coverage while nvidia does not. Use `SV_Coverage` to write to the coverage mask directly if you desire the same behavior across both vendors. `GetRenderTargetSampleCount()` can be used to get the current MSAA sample count to set the mask like so:
```c
float scaledAlpha = saturate(alpha) * GetRenderTargetSampleCount() + 0.5;
covMask = (1u << ((uint)(scaledAlpha))) - 1u;
```
Note: This mask is insufficient when using coarse pixels with VRS.
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

## [] Operator on Vectors and Arrays
There are a lot of quirks and pitfalls when dealing with arrays and vector indexing in HLSL.
dx11 does have the notion of dynamic indexable registers #x[] but fxc tries its hardest to avoid doing so.  
There are fundamentally 3 types of arrays:
- A vector of a primitive type like `float4 vec;`
- A constant buffer array which you declare with `static const float4 carr[2] = {...};`
- A modifiable array declared with `float4 arr[2];` using the indexable registers

When indexing into them to read and the index can be determined at compile time, fxc will just emit the values directly for all 3 types. Out of bounds indexing at compile time will cause a compile error for all 3 types as well.
### Dynamic Vector Indexing
`float result = vec[index];` will get compiled like this:
```c
static const float4 vectorIndexingArray[4] = {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
};
float result = dot(vec, vectorIndexingArray[index]);
```
This has a couple implications.
- If any component of `vec` is `NaN` or `+-Inf` the result will always be `NaN` regardless of index.
- All constant buffer arrays in the shader get put into a single immediate constant buffer. While out of bounds indexing a constant buffer is defined as returning 0, your original oob index might still point to a location inside that immediate constant buffer that has non zero data!
- You cannot write to vector components dynamically. `vec[index] = value;` will not compile if index is not known at compile time.
### Dynamic Constant Buffer Array Indexing
As already mentioned in the previous section, all constant buffer arrays land in the same constant buffer. oob reading one of your arrays might return data from other arrays instead of 0.
### Indexable Registers
Most forms of oob indexing like constant buffers, textures & uavs are defined to return 0. However indexable register oob is **undefined behavior**. Critically this has been reported to crash AMD gpus.

## Skipping draw call for material slot
Unity has a niche feature on materials to disable certain passes from materials. [material.SetShaderPassEnabled](https://docs.unity3d.com/ScriptReference/Material.SetShaderPassEnabled.html) can disable passes based on their **LightMode** tag, not pass name as one might expect. You can also edit this with the debug inspector in the editor under `Disabled Shader Passes`.  
If you make a shader that has exactly 1 pass with lightmode `Always` and then disable that pass on the material, Unity will skip the draw call entirely for that material. Two more tags that you will probably also want for this disabled material are `"IgnoreProjector" = "True"` and `"VRCFallback" = "Hidden"` to avoid the material rendering in projectors and with shaders blocked in VRChat respectively.

## Unity Animator Path Resolution
When using slashes in the name of game objects in the hierarchy, unity's animator will resolve paths in a way that can lead to unexpected results.
For example if you have a hierarchy like this:
```
- root
  - a/b
    - d
  - a/b/c
  - a
    - b
      - c
```
And you try to resolve the path `a/b/c` from `root`, you might expect it to resolve to the gameobject `c`. However it will  resolve to the gameobject `a/b/c` instead.  
For each child it tries to traverse the path from first child to last returning the first match for the full path. If you were to change the order of the children under root to be `a/b`, `a` and then `a/b/c`, the same path resolution would resolve to the gameobject `c` instead.  
This means you can not implement path resolution with a simple greedy algorithm as you might have to do backtracking like in this example.

## Unity Color Properties sRGB vs linear & animation
In this experiment, all four color properties start initialized to `0.5`:
- `_ColorLDRrgba`
- `_ColorHDRrgba`
- `_ColorLDRxyzw`
- `_ColorHDRxyzw`

When read back in shader:
- LDR properties show `0.2140411` (`0x3E5B2D9A`) for red, which indicates sRGB -> linear conversion.
- HDR properties show `0.5` (`0x3F000000`) for red, which stays in linear.

After running the animation clip (which animates values to `0.5`):
- All colors animated through `.rgba` curves read back as `0.2140411`.
- All colors animated through `.xyzw` curves read back as `0.5`.

This means recording an animation for an HDR color can produce different numeric results than what you picked in the color picker. The color picker value is linear, but the recorded `.rgba` animation curve is interpreted like sRGB-style color data, while `.xyzw` behaves like raw linear channels.

Exact repro setup: [`Experiments/ColorAnimation/`](Experiments/ColorAnimation/)

## Unity Post Processing Scalable Ambient Obscurance (SAO)
What you can find online is that SAO uses replacement shaders and relies on the shader's `RenderType` tag when rendering. If your shader does not define a `RenderType` tag, AO from other geometry can show through it.

Less well known is that SAO also does not behave correctly if the `ColorMask` ShaderLab command uses a material property, for example `ColorMask [_ColorMask]`. Replacing it with a literal value such as `ColorMask RGBA` fixes the issue.
