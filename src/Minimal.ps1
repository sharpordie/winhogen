Function Update-Nvidia {

    Param(
        [ValidateSet("Cuda", "GameReady")] [String] $Variety,
        [Switch] $NoBloat
    )

    Switch($Variety) {
        "Cuda" {
        }
        "GameReady" {
        }
    }

}