# Swift Consolidate Plugin

Consolidate files that match a predicate into a single file.

## Usage

### Arguments

<details>

<summary>embedded</summary>

</details>

<details>

<summary>recursive</summary>

</details>

### Build for embedded

Executing the following command will merge all Swift files contained in the given directory while removing imports and unnecessary whitespace, making it suitable for easy linking when building for embedded.

- `swift package plugin consolidate <directoryName> --embedded --recursive <outputFileName>`
