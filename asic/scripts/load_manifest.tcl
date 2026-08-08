proc load_rtl_manifest {repo_root manifest_path} {
    set rtl_files {}
    set manifest [open $manifest_path r]
    while {[gets $manifest line] >= 0} {
        set entry [string trim $line]
        if {$entry eq "" || [string match "#*" $entry]} {
            continue
        }
        set rtl_path [file normalize [file join $repo_root $entry]]
        if {![file exists $rtl_path]} {
            close $manifest
            error "RTL manifest entry does not exist: $rtl_path"
        }
        lappend rtl_files $rtl_path
    }
    close $manifest
    return $rtl_files
}
