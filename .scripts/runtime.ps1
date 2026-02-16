# 1. Fetch the DuckCraft code
$sourceUrl = "https://omidomidvari.github.io"
$htmlContent = (Invoke-WebRequest -Uri $sourceUrl).Content

# 2. Inject the Sync Script to handle shared variables (excluding position)
$syncScript = @"
<script>
    window.sharedState = {};
    async function syncData() {
        // Exclude local 'position' from being overwritten or sent
        const dataToSend = { ...window.sharedState };
        delete dataToSend.position; 

        try {
            const res = await fetch('/sync', {
                method: 'POST',
                body: JSON.stringify(dataToSend)
            });
            const updated = await res.json();
            // Update local variables except position
            Object.keys(updated).forEach(key => {
                if (key !== 'position') window.sharedState[key] = updated[key];
            });
        } catch (e) { console.error("Sync failed", e); }
    }
    setInterval(syncData, 1000); // Sync every second
</script>
"@
$htmlContent = $htmlContent.Replace("</body>", "$syncScript</body>")

# 3. Setup the HTTP Server
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/")
$listener.Start()
$sharedVars = @{} # This holds the variables on the server

Write-Host "Server started at http://localhost:8080. Press Ctrl+C to stop." -ForegroundColor Green
Start-Process "http://localhost:8080"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        if ($request.Url.LocalPath -eq "/sync" -and $request.HttpMethod -eq "POST") {
            # Update shared variables from client
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $json = $reader.ReadToEnd()
            if ($json) {
                $clientData = $json | ConvertFrom-Json
                foreach ($prop in $clientData.PSObject.Properties) {
                    $sharedVars[$prop.Name] = $prop.Value
                }
            }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes(($sharedVars | ConvertTo-Json))
        } else {
            # Serve the modified HTML
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
        }

        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
} finally {
    $listener.Stop()
}
