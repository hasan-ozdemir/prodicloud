# Shared 'quiet' command option specification.

function Get-ClagnosSharedQuietOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'quiet' -ShortNames @('q'))
}
