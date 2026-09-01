"Run the video-recording suite."
function test_video()
    @testset "ProjecturedVideo" begin
        test_record_video()
    end
end

export test_video, test_record_video
