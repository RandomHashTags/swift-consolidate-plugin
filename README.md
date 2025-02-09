# Swift Consolidate Plugin

Consolidate files that match a predicate into a single file.

## Usage

The arguments can be declared in any order, and you can mix and match them (embedded + production outputs a file suitable only for production usage on an embedded device).

### Arguments

<details>

<summary>embedded</summary>

Strips imports, unnecessary whitespace (preserving comments and documentation) and code annotated to not work for embedded.

</details>

<details>

<summary>exclude</summary>

Exclude directories/files when consolidating.

- Usage: `--exclude <comma separated list of directories/files, relative to the package directory path>`

</details>

<details>

<summary>lang</summary>

What programming languages you want to consolidate.

- Usage: `--lang <comma separated list of a supported programming language name>`

- Supported Programming Languages
  - C (coming soon)
  - Swift
  - Rust (coming soon)

</details>

<details>

<summary>production</summary>

Strips all redundant information and unnecessary whitespace, including comments and documentation, leaving just the bare minimum required to use the code.

</details>

<details>

<summary>recursive</summary>

Searches all directory contents.

</details>

<details>

<summary>output</summary>

The single file output path where the consolidated data gets written to, relative to the package directory.

</details>

### Build for embedded

Executing the following command will merge all Swift files contained in the given directory while removing imports and unnecessary whitespace, making it suitable for easy linking when building for embedded.

- `swift package plugin consolidate <sourceDirectory> --embedded --recursive --output <outputPath>`
