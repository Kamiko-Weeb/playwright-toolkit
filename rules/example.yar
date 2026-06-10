/*
 * Example YARA rules for the virus scanner.
 *
 * These are an OPTIONAL detection layer. They are only used when the
 * `yara-python` package is installed (`pip install yara-python`). Without it,
 * the scanner runs fine on its built-in hash + pattern + entropy layers.
 *
 * Drop more .yar files in this folder to extend coverage. YARA is the format
 * most real malware-detection feeds (e.g. from threat-intel sharing) ship in.
 */

rule EICAR_Test_File
{
    meta:
        description = "Standard EICAR antivirus test string (harmless)"
        severity    = "test"
    strings:
        $eicar = "EICAR-STANDARD-ANTIVIRUS-TEST-FILE"
    condition:
        $eicar
}

rule Suspicious_Shell_Dropper
{
    meta:
        description = "Pipes a remote script straight into a shell"
        severity    = "suspicious"
    strings:
        $curl_sh = /(curl|wget)\s+[^\n|]*\|\s*(sh|bash)/
    condition:
        $curl_sh
}

rule Suspicious_PowerShell_Download
{
    meta:
        description = "In-memory download-and-execute via PowerShell"
        severity    = "suspicious"
    strings:
        $webclient = "Net.WebClient" nocase
        $download  = "DownloadString" nocase
        $iex       = "IEX(" nocase
    condition:
        2 of them
}
