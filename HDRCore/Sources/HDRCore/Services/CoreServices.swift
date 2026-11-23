import Foundation

/// Every platform capability the Core needs, injected through the constructor
/// (RE:Flex: "one module with no UI imports, constructed with every platform
/// capability passed in"). The only UI-coupled piece is the folder picker,
/// which the app target supplies.
public struct CoreServices: Sendable {
    public var chooseExportFolder: @Sendable () async -> URL?
    public var mediaLoader: any MediaLoader
    public var toneMapper: any ToneMapper
    public var exporter: any SDRExporter

    public init(
        chooseExportFolder: @escaping @Sendable () async -> URL?,
        mediaLoader: any MediaLoader,
        toneMapper: any ToneMapper,
        exporter: any SDRExporter
    ) {
        self.chooseExportFolder = chooseExportFolder
        self.mediaLoader = mediaLoader
        self.toneMapper = toneMapper
        self.exporter = exporter
    }

    /// Production wiring. All heavy lifting (ImageIO / CoreGraphics / CoreImage /
    /// AVFoundation) lives in the Core; only the folder picker comes from the app.
    public static func live(chooseExportFolder: @escaping @Sendable () async -> URL?) -> CoreServices {
        let toneMapper = CoreGraphicsToneMapper()
        return CoreServices(
            chooseExportFolder: chooseExportFolder,
            mediaLoader: LiveMediaLoader(toneMapper: toneMapper),
            toneMapper: toneMapper,
            exporter: LiveSDRExporter(toneMapper: toneMapper)
        )
    }
}
