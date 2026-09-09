# Mono TabBar design proposals

Status: raster concepts generated with built-in image_gen; all three proposals approved for integration. SwiftUI implementation is in progress. Runtime verification is not complete.

## Confirmed scope

- Produce both a native system TabBar direction and a Mono custom TabBar direction.
- Do not constrain this redesign to previously generated icons. Neutral system symbols are placeholders for evaluating the structure.
- Keep the four current destinations: 首页、播客、音乐库、我的.
- Include light and dark appearances and the existing playback / next / queue actions.

## Proposals

- A: native system glass tab bar with a separate bottom accessory, cover and two-line metadata.
- B: custom integrated dock with playback above navigation.
- C: custom separated floating bars with pause integrated into the cover.

The user explicitly approved integrating all three proposals: A, B and C. All three belong to the System Tab Bar setting. The original twelve floating bar styles remain a separate list in their original order.

The PNGs are AI-generated concept images, not app screenshots or runtime evidence. Album thumbnails are illustrative. Native material, selection geometry and minimized layouts remain controlled by iOS; the generated native silhouette is not an exact UIKit pixel contract. Navigation identity and the existing version/device-specific fallback must be preserved during implementation.

Prompts and generation metadata are saved next to each image as a.prompt.json, b.prompt.json and c.prompt.json.
