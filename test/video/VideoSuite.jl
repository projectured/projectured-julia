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

"Run the video-recording suite."
function test_video()
    @testset "ProjecturedVideo" begin
        test_record_video()
    end
end

export test_video, test_video_layering, test_record_video
