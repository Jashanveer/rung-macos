#!/usr/bin/env swift

/*
 parse_health_export.swift

 Reads an Apple Health "Export All Health Data" `export.xml` and emits a
 sleep CSV you can compare against Rung's own inferred windows. Useful
 for calibrating the cross-device foreground tracker against
 Apple-Watch-derived ground truth (or against RISE's output, which RISE
 writes back to Apple Health).

 Usage:
   swift scripts/parse_health_export.swift /path/to/export.xml > sleep.csv

 Output columns:
   start_iso8601,end_iso8601,duration_minutes,source_name,value

 The CSV includes only HKCategoryTypeIdentifierSleepAnalysis records.
 Other Apple Health categories are ignored.
*/

import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: parse_health_export.swift <export.xml>\n".utf8))
    exit(64)
}

let inputPath = CommandLine.arguments[1]
let url = URL(fileURLWithPath: inputPath)

guard FileManager.default.fileExists(atPath: url.path) else {
    FileHandle.standardError.write(Data("error: file not found: \(url.path)\n".utf8))
    exit(66)
}

guard let stream = InputStream(url: url) else {
    FileHandle.standardError.write(Data("error: cannot open \(url.path)\n".utf8))
    exit(66)
}

final class SleepRecordHandler: NSObject, XMLParserDelegate {
    let isoIn: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    let healthDateFormat: DateFormatter = {
        // Apple Health export uses "yyyy-MM-dd HH:mm:ss Z"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()
    let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    var recordCount: Int = 0
    var sleepCount: Int = 0

    func parse(start: String, end: String, source: String, value: String) {
        guard let s = healthDateFormat.date(from: start),
              let e = healthDateFormat.date(from: end) else { return }
        let mins = Int(round(e.timeIntervalSince(s) / 60))
        let cleanSource = source.replacingOccurrences(of: ",", with: ";")
        let cleanValue = value.replacingOccurrences(of: "HKCategoryValueSleepAnalysis", with: "")
        let line = "\(isoOut.string(from: s)),\(isoOut.string(from: e)),\(mins),\(cleanSource),\(cleanValue)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        sleepCount += 1
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Record" else { return }
        recordCount += 1
        guard let type = attributeDict["type"], type == "HKCategoryTypeIdentifierSleepAnalysis",
              let start = attributeDict["startDate"],
              let end = attributeDict["endDate"] else { return }
        let source = attributeDict["sourceName"] ?? ""
        let value = attributeDict["value"] ?? ""
        parse(start: start, end: end, source: source, value: value)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        FileHandle.standardError.write(Data("xml parse error: \(parseError.localizedDescription)\n".utf8))
    }
}

let parser = XMLParser(stream: stream)
let handler = SleepRecordHandler()
parser.delegate = handler

// Header
FileHandle.standardOutput.write(Data("start_iso8601,end_iso8601,duration_minutes,source_name,value\n".utf8))

if !parser.parse() {
    FileHandle.standardError.write(Data("error: xml parse failed\n".utf8))
    exit(70)
}

FileHandle.standardError.write(Data("scanned \(handler.recordCount) records, emitted \(handler.sleepCount) sleep rows\n".utf8))
