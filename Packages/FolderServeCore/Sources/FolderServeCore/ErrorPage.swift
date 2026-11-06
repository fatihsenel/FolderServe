import Foundation

public enum ErrorPage {
    public static func html(status: Int, message: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(status)</title><style>\(PageStyle.css)</style></head>
        <body><main><h1>\(status)</h1><p>\(PageStyle.escape(message))</p></main></body></html>
        """
    }
}
