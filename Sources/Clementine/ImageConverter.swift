import UniformTypeIdentifiers

struct ImageConverter: Converter {
    let inputs: [UTType] = [.jpeg, .png, .heic, .tiff, .gif, .bmp, .webP]
    let outputs: [OutputFormat] = [.jpeg, .png, .heic, .tiff, .pdf]
}
