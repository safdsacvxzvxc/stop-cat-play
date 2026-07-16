[CmdletBinding()]
param(
    [switch] $NoBrowser
)

$ErrorActionPreference = "Stop"

$root = [System.IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path))
$listener = $null
$port = 8765

while ($port -le 8795) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        $listener.Start()
        break
    }
    catch {
        if ($listener) {
            $listener.Stop()
        }
        $listener = $null
        $port++
    }
}

if (-not $listener) {
    throw "Could not find an available local port."
}

function Get-ContentType([string] $path) {
    $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -eq ".gz") {
        $extension = [System.IO.Path]::GetExtension(
            [System.IO.Path]::GetFileNameWithoutExtension($path)
        ).ToLowerInvariant()
    }

    switch ($extension) {
        ".html" { return "text/html; charset=utf-8" }
        ".js"   { return "application/javascript" }
        ".wasm" { return "application/wasm" }
        ".data" { return "application/octet-stream" }
        ".json" { return "application/json; charset=utf-8" }
        ".css"  { return "text/css; charset=utf-8" }
        ".png"  { return "image/png" }
        ".ico"  { return "image/x-icon" }
        default  { return "application/octet-stream" }
    }
}

function Send-Response(
    [System.Net.Sockets.NetworkStream] $stream,
    [int] $statusCode,
    [string] $statusText,
    [byte[]] $body,
    [string] $contentType,
    [bool] $gzip
) {
    $headers = "HTTP/1.1 $statusCode $statusText`r`n" +
        "Content-Type: $contentType`r`n" +
        "Content-Length: $($body.Length)`r`n" +
        "Cache-Control: no-cache`r`n" +
        $(if ($gzip) { "Content-Encoding: gzip`r`n" } else { "" }) +
        "Connection: close`r`n`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($body.Length -gt 0) {
        $stream.Write($body, 0, $body.Length)
    }
}

$url = "http://127.0.0.1:$port/"
Write-Host "Ball Alchemy is running at $url"
Write-Host "Keep this window open while playing. Close it to stop the game server."
if (-not $NoBrowser) {
    Start-Process $url
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
            $requestLine = $reader.ReadLine()

            while ($reader.ReadLine()) { }

            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }

            $parts = $requestLine.Split(' ')
            if ($parts.Length -lt 2 -or $parts[0] -ne "GET") {
                $body = [System.Text.Encoding]::UTF8.GetBytes("Method not allowed")
                Send-Response $stream 405 "Method Not Allowed" $body "text/plain; charset=utf-8" $false
                continue
            }

            $requestPath = [System.Uri]::UnescapeDataString($parts[1].Split('?')[0])
            if ($requestPath -eq "/") {
                $requestPath = "/index.html"
            }

            $relativePath = $requestPath.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $filePath = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
            $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

            if (-not $filePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not [System.IO.File]::Exists($filePath)) {
                $body = [System.Text.Encoding]::UTF8.GetBytes("Not found")
                Send-Response $stream 404 "Not Found" $body "text/plain; charset=utf-8" $false
                continue
            }

            $body = [System.IO.File]::ReadAllBytes($filePath)
            $gzip = [System.IO.Path]::GetExtension($filePath).Equals(".gz", [System.StringComparison]::OrdinalIgnoreCase)
            Send-Response $stream 200 "OK" $body (Get-ContentType $filePath) $gzip
        }
        catch {
            Write-Warning $_.Exception.Message
        }
        finally {
            $client.Close()
        }
    }
}
finally {
    $listener.Stop()
}
