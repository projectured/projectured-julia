"""
    test_video_layering()

Static layered-architecture guard for `ProjecturedVideo`.
"""
function test_video_layering()
    main = get_package_source_root(ProjecturedVideo)
    check_layering(main, pathof(ProjecturedVideo);
                   name = "video",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedVideo; all = true)
                         if isdefined(ProjecturedVideo, n) &&
                            getfield(ProjecturedVideo, n) isa Module &&
                            getfield(ProjecturedVideo, n) !== ProjecturedVideo &&
                            parentmodule(getfield(ProjecturedVideo, n)) !== ProjecturedVideo))
end

"Run this package's whole suite: the layering guard and every video test."
function test_video()
    @testset "ProjecturedVideo" begin
        test_video_layering()
        test_record_video()
        test_application_video()
    end
end

export test_video, test_video_layering, test_record_video, test_application_video
