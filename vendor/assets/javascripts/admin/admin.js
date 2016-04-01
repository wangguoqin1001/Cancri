/**
 * Created by huaxiukun on 16/2/25.
 */
$(function () {

    // 裁判审核
    $('.update-cw-id').on('click', function () {
        var ckd = $(this).attr('data-id');
        $('.review-referee-info-submit').on('click', function () {
            var status = $(".referee-apply-status [name='referee-apply']:checked").val();
            var comp_wd = $(".comp-worker-" + ckd).val();
            if (ckd) {
                console.log(status);
                if (!status) {
                    alert('请选择审核结果');
                    return false;
                }
                $.ajax({
                    url: '/admin/checks/review_referee',
                    type: 'post',
                    data: {
                        "status": status, "comp_wd": comp_wd
                    },
                    success: function (data) {
                        if (data[0]) {
                            alert(data[1]);
                            window.location.reload();
                        } else {
                            alert(data[1]);
                        }
                    }
                });
                $(".referee-apply-status [name='referee-apply']").prop('checked', false);
            } else {
                alert('审核对象不存在');
            }
        });

    });
    // 教师审核
    $(".teacher-apply-status [name='teacher-apply']").on('click', function () {
        var status = $(".teacher-apply-status [name='teacher-apply']:checked").val();
        if (status == 1) {
            $(".teacher-apply-level").removeClass('hide');
        } else {
            $(".teacher-apply-level").addClass('hide');
        }
    });
    $('.review-teacher-info-submit').on('click', function () {
        var level;
        var status = $(".teacher-apply-status [name='teacher-apply']:checked").val();

        if (status) {
            level = $(".teacher-apply-level [name='teacher-apply-level']:checked").val();
            if (!level && status == 1) {
                alert('请选择老师级别');
                return false;
            }
            $.ajax({
                url: '/admin/checks/review_teacher',
                type: 'post',
                data: {
                    "status": status, "level": level
                },
                success: function (data) {
                    if (data[0]) {
                        alert(data[1]);
                        window.location.reload();
                    } else {
                        alert(data[1]);
                    }
                }
            });
        } else {
            alert('请选择审核结果');
        }

        $(".teacher-apply-status [name='teacher-apply']").prop("checked", false);
        $(".teacher-apply-level [name='teacher-apply-level']").prop("checked", false);
    });
    $('.btn-search-toggle').on('click', function () {
        $('.form-search-toggle').toggleClass('hide show');
    });
    $(".edit-schedule-submit").on('click', function (e) {
        e.preventDefault();
        var sd = $(this).attr('data-id');
        var name = trim($('#schedule-name' + sd).val());
        var start_time = trim($('#schedule-start-time' + sd).val());
        var end_time = trim($('#schedule-end-time' + sd).val());

        if (name == '') {
            alert('名称不能为空！');
            $('#schedule-name' + sd).focus();
            return false;
        }
        if (start_time == '') {
            alert('开始时间不能为空！');
            $('#schedule-start-time' + sd).focus();
            return false;
        }
        $.ajax({
            url: '/admin/competition_schedules/update_cs',
            type: 'post',
            data: {
                "name": name, "sd": sd, "start_time": start_time, "end_time": end_time
            },
            success: function (data) {
                alert(data[1]);
                if (data[0]) {
                    window.location.reload();
                }


            },
            error: function (data) {
                alert(data[1]);
            }
        });
    });
});
function trim(str) {
    return str.replace(/(^\s*)|(\s*$)/g, "");
}