class Admin::EventsController < AdminController
  before_action :set_event, only: [:show, :edit, :update, :destroy, :scores, :school_sort]

  before_action do
    authenticate_permissions(['editor', 'admin'])
  end

  # GET /admin/events
  # GET /admin/events.json
  def index
    events = Event.includes(:parent_event).joins(:competition).order('competition_id desc,is_father desc, parent_id'); false
    if params[:field].present? && params[:keyword].present?
      if params[:field] == 'competition'
        events = events.where(["competitions.name like ?", "%#{params[:keyword]}%"])
      else
        events = events.where(["events.#{params[:field]} like ?", "%#{params[:keyword]}%"])
      end
    end
    @events= events.select('events.*', 'competitions.name as comp_name').page(params[:page]).per(params[:per])

    respond_to do |format|
      format.html
      format.xls {
        data = @events.order('competition_id desc,is_father desc').map { |x| {
            所属比赛: x.comp_name,
            名称: x.name,
            组别名: x.is_father ? '是' : nil,
            包含组别: x.group.gsub(/[1-4]/, '1' => '小', '2' => '中', '3' => '初', '4' => '高'),
            队伍允许人数: x.is_father ? nil : "#{x.team_min_num}"+"#{x.team_max_num>1 ? "-#{x.team_max_num}" : nil}",
        } }
        filename = "Event-Export-#{Time.now.strftime("%Y%m%d%H%M%S")}.xls"
        send_data(data.to_xls, :type => "text/xls;charset=utf-8,header=present", :filename => filename)
      }
    end
  end

  # GET /admin/events/1
  # GET /admin/events/1.json
  def show
    unless @event.is_father
      @event_schedules = EventSchedule.joins(:schedule).where(event_id: @event.id, group: @event.group.split(',')[0]).select(:id, :event_id, :schedule_id, 'schedules.name as schedule_name').map { |x| {
          id: x.id,
          event_id: x.event_id,
          schedule_id: x.schedule_id,
          schedule_name: x.schedule_name,
          score_attrs: EventSaShip.joins(:score_attribute).where(event_id: x.event_id, schedule_id: x.schedule_id).select(:id, 'score_attributes.name', :formula, :desc)
      } }
      EventSaShip.joins(:score_attribute).where(event_id: 35, schedule_id: 13).select(:id, 'score_attributes.name', :formula)
      @score_attributes = EventSaShip.includes(:score_attribute, :score_attribute_parent).where(event_id: params[:id], is_parent: 0).where.not(score_attribute_id: 0).order('sort asc').map { |s| {
          id: s.id,
          name: s.level==1 ? s.score_attribute.name : s.score_attribute_parent.name+': '+ s.score_attribute.name,
          write_type: s.score_attribute.write_type,
          desc: s.score_attribute.try(:desc),
          sort: s.sort,
          formula: s.formula
      } }
    end
  end

  def edit_event_sa_desc
    desc = params[:desc]
    sa_id = params[:sa_id]
    if desc.present? && sa_id.present?
      sa_ship = EventSaShip.find_by_id(sa_id)
      if sa_ship
        sa_ship.desc = desc
        if sa_ship.save
          result = [true, '操作成功 ']
        else
          result = [false, '更改失败']
        end
      else
        result = [false, '参数不规范']
      end
    else
      result = [false, '参数不完整']
    end
    render json: result
  end


  # GET /admin/events/new
  def new
    @event = Event.new
  end

  # GET /admin/events/1/edit
  def edit
  end

  def scores
    event_id = params[:id]
    params_group = params[:group]
    sort = params[:sort]
    group = 0
    case params_group
      when '小学组'
        group = 1
      when '中学组'
        group = 2
      when '初中组'
        group = 3
      when '高中组'
        group = 4
      else
        render_optional_error(404)
    end
    if sort.to_i == 1
      event_sa = EventSaShip.where(event_id: event_id, score_attribute_id: 19).take
      if event_sa.present? && event_sa.formula.present?
        order = event_sa.formula['order']
        order_num = order['num']
        first_order = (order['1']['sort'].to_i == 0) ? '>' : '<'
        if order_num == 2
          second_order = order['2']['sort'].to_i
          teams = Team.joins('inner join scores s on s.team1_id = teams.id').where(event_id: event_id, group: group).where('s.score > ?', 0).select('teams.*', 's.score', 's.order_score').order("s.score #{(first_order == '>') ? 'desc' : 'asc'}").order("s.order_score #{(second_order == 1) ? 'asc' : 'desc'}")
          if teams.present?
            teams.each_with_index do |team, index|
              team.update(rank: index+1)
            end
            flash[:notice] = '排名成功'
          end
        else
          # 单一排序
          sql = "rank = (select count(*)+1 from (select score from scores s left join teams team on team.id = s.team1_id where team.event_id =#{event_id} and team.group=#{group} and s.score > 0) dist_score where dist_score.score #{first_order} scores.score)"
          if Team.joins('inner join scores on scores.team1_id = teams.id').where(event_id: event_id, group: group).where('scores.score > ?', 0).update_all(sql)
            flash[:notice] = '排名成功'
          else
            flash[:notice] = '排名失败'
          end
        end
      else
        flash[:notice] = '公式不存在'
        redirect_to "/admin/events/scores?id=#{event_id}&group=#{params_group}"
        return false
      end
    end
    @scores = Team.left_joins(:school).joins('left join user_profiles u_p on u_p.user_id = teams.user_id').joins('left join scores s on teams.id = s.team1_id').where(event_id: event_id, group: group).select(:id, 'schools.name as school_name', 's.score', 's.score_attribute', 's.order_score', 'u_p.username', 'teams.teacher', 'teams.rank', 'teams.group', 'teams.identifier').order('teams.rank asc')
  end

  def school_sort
    event_id = params[:id]
    params_group = params[:group]
    group = 0
    if params_group.present?
      case params_group
        when '小学组'
          group = '(1)'
        when '中学组'
          group = '(2, 3, 4)'
        else
          render_optional_error(404)
      end
    end

    if @event.is_father
      event_ids = @event.child_events.pluck(:id)
      if event_ids.present?
        events_num = event_ids.length
        event_ids = '('+event_ids.join(',')+')'
        @schools = Team.find_by_sql("select s.id,s.name as school_name,count(distinct t.event_id) as join_event_num,GROUP_CONCAT(distinct t.event_id) as event_ids from teams t left join schools s on t.school_id = s.id where t.event_id in #{event_ids} and t.group in #{group} GROUP BY t.school_id")
        if @schools.present?
          @school_array = @schools.map { |school| {
              id: school.id,
              school_name: school.school_name,
              join_event_num: school.join_event_num,
              event_ids: school.event_ids,
              ranks: school_first_ranks(school.id, school.event_ids, group)
          } }.map { |s| {
              id: s[:id],
              school_name: s[:school_name],
              join_event_num: s[:join_event_num],
              event_ids: s[:event_ids],
              points: (events_num-s[:join_event_num])*100+s[:ranks][0],
              ranks: s[:ranks][1]
          } }.sort_by { |h| [h[:points], -h[:join_event_num]] }
          @all_points = @school_array.pluck(:points).uniq
        else
          flash[:notice] = '没有学校参加该项目'
        end
      else
        flash[:notice] = '没有子项目'
      end
    else
      @schools = Team.find_by_sql("select s.id,s.name as school_name,count(t.id) as join_event_num,GROUP_CONCAT(t.rank) as ranks from teams t left join schools s on t.school_id = s.id where t.event_id = #{event_id} and t.group in #{group} GROUP BY t.school_id")
      if @schools.present?
        @school_array = @schools.map { |s| {
            id: s.id,
            school_name: s.school_name,
            join_event_num: s.join_event_num,
            ranks: s.ranks,
            points: ((s.ranks.to_s.split(',')[0].to_i == 0 ? 100 : s.ranks.to_s.split(',')[0].to_i)+(s.ranks.to_s.split(',')[1].to_i == 0 ? 100 : s.ranks.to_s.split(',')[1].to_i)+(s.ranks.to_s.split(',')[2].to_i == 0 ? 100 : s.ranks.to_s.split(',')[2].to_i))
        } }.sort_by { |h| [h[:points], -h[:join_event_num]] }
        @all_points = @school_array.pluck(:points).uniq
      else
        flash[:notice] = '没有学校参加该项目'
      end
    end
  end

  def teams
    status = params[:status]
    event_id = params[:id]
    @event = Event.find(event_id)
    teams = Team.includes(:team_user_ships, :user).where(event_id: event_id)
    if status.present?
      case status
        when '组队中' then
          status = 0
        when '报名成功' then
          status = 1
        when '待学校审核' then
          status = 2
        when '待区县审核' then
          status = 3
        when '学校拒绝' then
          status = -2
        when '区县拒绝' then
          status = -3
        else
          status = nil
      end
      teams = teams.where(status: status)
    end
    @teams = teams.page(params[:page]).per(params[:per])
    @users = User.includes(:user_profile).where.not(id: TeamUserShip.where(event_id: params[:id]).pluck(:user_id)).select(:id, :nickname)
  end

  def add_team_player
    user_id = params[:user_id]
    team_id = params[:team_id]
    event_id = params[:event_id]
    if user_id.present? && team_id.present? && event_id.present?
      if TeamUserShip.where(user_id: user_id, event_id: event_id, team_id: team_id).exists?
        result = [false, '该队员已报名该项目,不能添加']
      else
        user_profile = UserProfile.find_by_user_id(user_id)
        if user_profile.present? && user_profile.school_id.to_i !=0 && user_profile.district_id.to_i !=0 && user_profile.grade.to_i !=0
          team_user = TeamUserShip.create(user_id: user_id, event_id: event_id, team_id: team_id, school_id: user_profile.school_id, district_id: user_profile.district_id, grade: user_profile.grade, status: true)
          if team_user.save
            result = [true, '添加成功']
          else
            result = [false, '添加失败']
          end
        else
          result = [false, '该队员还没有添加学校和年级']
        end
      end
    else
      result = [false, '参数不完整']
    end
    render json: result
  end

  def update_team_player
    new_user_id = params[:new_user_id]
    old_user_id = params[:old_user_id]
    team_id = params[:team_id]
    event_id = params[:event_id]
    if new_user_id.to_i !=0 && old_user_id.to_i !=0 && team_id.to_i !=0 && event_id.to_i !=0
      if TeamUserShip.where(user_id: new_user_id, event_id: event_id, team_id: team_id).exists?
        result = [false, '新队员已报名该项目,无法替换']
      else
        user_profile = UserProfile.find_by_user_id(new_user_id)
        if user_profile.present? && user_profile.school_id.to_i !=0 && user_profile.district_id.to_i !=0 && user_profile.grade.to_i !=0
          leader = Team.where(user_id: old_user_id, id: team_id).take
          t_u = TeamUserShip.where(team_id: team_id, user_id: old_user_id).take
          if leader.present?
            if leader.update(user_id: new_user_id)
              if t_u.update(user_id: new_user_id)
                result = [true, '更换成功']
              else
                leader.update(user_id: old_user_id)
                result = [false, '更换失败']
              end
            else
              result = [false, '更换失败']
            end
          else
            if t_u.update(user_id: new_user_id)
              result = [true, '更换成功']
            else
              result = [false, '更换失败']
            end
          end
        else
          result = [false, '该队员还没有添加学校和年级']
        end
      end
    else
      result = [false, '参数不完整']
    end
    render json: result
  end

  def delete_team_player
    user_id = params[:user_id]
    team_id = params[:team_id]
    player = TeamUserShip.where(user_id: user_id, team_id: team_id).take
    player.destroy
    if player.destroy
      result = [true, '删除成功']
    else
      result = [false, '删除失败']
    end
    render json: result
  end

  def create_team
    user_id = params[:user_id]
    event_id = params[:event_id]
    group = params[:group]
    teacher = params[:teacher]
    if teacher.present? && group.to_i !=0 && event_id.to_i !=0 && user_id.to_i !=0
      t = TeamUserShip.where(user_id: user_id, event_id: event_id).take
      if t.present?
        result = [false, '该队员已经报名该项目,无法创建']
      else
        u_p = UserProfile.find_by_user_id(user_id)
        if u_p.present? && u_p.school_id.to_i !=0 && u_p.district_id.to_i !=0 && u_p.grade.to_i !=0
          team = Team.create(user_id: user_id, event_id: event_id, teacher: teacher, school_id: u_p.school_id, district_id: u_p.district_id, group: group, status: 1)
          if team.save
            t_u = TeamUserShip.create(team_id: team.id, user_id: user_id, event_id: event_id, status: true, school_id: u_p.school_id, district_id: u_p.district_id, grade: u_p.grade)
            if t_u.save
              result = [true, '队伍创建成功']
            end
          else
            team.destroy
            result = [false, team.error.full_messages.first]
          end
        else
          result = [false, '该队员还没有添加学校和班级']
        end
      end
    else
      result = [false, '参数不完整']
    end
    render json: result
  end

  def delete_team
    Team.delete(params[:team_id])
    players = TeamUserShip.where(team_id: params[:team_id])
    players.delete_all
    if players.delete_all
      result = [true, '删除成功']
    else
      result = [false, '删除失败']
    end
    render json: result
  end

  def update_formula
    formula = params
    sa_id = params[:sa_id]
    order = params[:order]
    if order.present? && order.is_a?(Array) && sa_id.present?
      new_order = {}
      order.each_with_index do |o, index|
        split_order = o.split('++')
        new_order[index+1] = {id: split_order[0].to_i, sort: split_order[1].to_i, name: split_order[2]}
      end
      new_order[:num] = order.length
      gs = formula["formula"]

      if gs.is_a?(Array) && gs.length>0
        gs.each do |g|
          if g[:molecule].to_i !=0 && g[:denominator].to_i !=0
            g[:xishu] = (g[:molecule].to_f/g[:denominator].to_f).round(2)
          else
            result = [false, '公式格式不规范']
            render json: {status: result[0], message: result[1]}
            return false
          end
        end
      end

      if new_order[1][:id] != 0
        result = [false, '成绩排序中要包含最终成绩排序']
      else
        event_sa = EventSaShip.find_by_id(sa_id)
        if event_sa.present?
          formula.delete(:sa_id)
          formula.delete(:action)
          formula.delete(:controller)
          formula[:order] = new_order
          if event_sa.update(formula: formula)
            result = [true, '操作成功']
          else
            result = [false, '操作失败']
          end
        else
          result=[false, '不规范请求']
        end
      end
    else
      result=[false, '参数不完整']
    end
    render json: {status: result[0], message: result[1]}
  end


  def add_score_attributes
    if request.method == 'POST'
      ed = params[:ed]
      sa_ids = params[:sa_ids]
      schedule_id = params[:schedule_id]
      # parent_id = params[:parent_id]
      # if sa_ids.present? && parent_id.present?
      #   parent_sa = EventSaShip.where(event_id: ed, score_attribute_id: parent_id, level: 1).take
      #   if parent_sa.present?
      #     unless parent_sa.is_parent
      #       parent_sa.update_attributes(is_parent: 1)
      #     end
      #   else
      #     EventSaShip.create!(event_id: ed, score_attribute_id: parent_id, is_parent: 1)
      #   end
      #   sa_ids.each do |sa_id|
      #     esa = EventSaShip.where(event_id: ed, score_attribute_id: sa_id, parent_id: parent_id).take
      #     unless esa.present?
      #       EventSaShip.create!(event_id: ed, score_attribute_id: sa_id, parent_id: parent_id, level: 2)
      #     end
      #   end
      if sa_ids.present? && sa_ids.is_a?(Array) && ed.present? && schedule_id.present?
        all_result = []
        sa_ids.each do |sa_id|
          esa = EventSaShip.where(event_id: ed, score_attribute_id: sa_id, schedule_id: schedule_id, level: 1).take
          unless esa.present?
            new_row = EventSaShip.create(event_id: ed, schedule_id: schedule_id, score_attribute_id: sa_id, is_parent: false)
            unless new_row.save
              all_result << false
            end
          end
        end
        if all_result.include?(false)
          result = [true, '有未添加成功的属性']
        else
          result = [true, '添加成功']
        end
      else
        result = [false, '参数不规范']
      end
      render json: {status: result[0], message: result[1]}
    end
  end

  def delete_score_attribute
    sa_id = params[:sa_id]
    if sa_id.present?
      sa = EventSaShip.find_by_id(sa_id)
      if sa.present?
        formulas = EventSaShip.where(event_id: sa.event_id).pluck(:formula)
        has_use = []
        formulas.each do |f|
          if f.present? && f.is_a?(Hash)
            f.to_a.each do |f_attr|
              if f_attr[0] == sa_id
                has_use << true
              end
            end
          end
        end
        if has_use.include?(true)
          result = [false, '该属性在公式里,无法删除']
        else
          if EventSaShip.delete(sa_id)
            result = [true, '删除成功']
          else
            result = [false, '删除失败']
          end
        end
      else
        result = [false, '对象不存在']
      end
    else
      result = [false, '参数不完整']
    end
    render json: result
  end

  def update_score_attrs_sort
    ids = params[:ids]
    event_id = params[:event_id]

    if event_id && ids && ids.is_a?(Array)
      event_sas = EventSaShip.where(event_id: event_id)
      if event_sas && ((event_sas.pluck(:id).map { |x| x.to_s } & ids).count == ids.length)
        update_attrs_json = {}
        ids.each_with_index do |id, index|
          update_attrs_json[id.to_i] ={sort: index+1}
        end
        EventSaShip.update(update_attrs_json.keys, update_attrs_json.values)
        result ={status: true, message: '更新成功'}
      else
        result ={status: false, message: '不规范请求'}
      end
    else
      result ={status: false, message: '不规范请求'}
    end
    render json: result
  end

  # POST /admin/events
  # POST /admin/events.json
  def create
    @event = Event.new(event_params)

    respond_to do |format|
      if @event.save
        format.html { redirect_to [:admin, @event], notice: '比赛项目创建成功' }
        format.json { render action: 'show', status: :created, location: @event }
      else
        format.html { render action: 'new' }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end


  # PATCH/PUT /admin/events/1
  # PATCH/PUT /admin/events/1.json
  def update
    respond_to do |format|
      if @event.update(event_params)
        format.html { redirect_to [:admin, @event], notice: '比赛项目更新成功' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @event.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/events/1
  # DELETE /admin/events/1.json
  def destroy
    if @event.is_father && Event.where(parent_id: @event.id).exists?
      flash[:notice]='该组名不能删除(目前还包含项目)'
      redirect_back(fallback_location: admin_events_path)
    else
      @event.destroy
      respond_to do |format|
        format.html { redirect_to admin_events_url, notice: '比赛项目删除成功' }
        format.json { head :no_content }
      end
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_event
    @event = Event.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def event_params
    params.require(:event).permit(:name, :is_father, :parent_id, :competition_id, :level, :cover, :description, :body_html, :status, :against, :team_min_num, :team_max_num, :apply_start_time, :apply_end_time, :start_time, :end_time, {group: []}).tap do |e|
      if params[:event][:group].present?
        e[:group] = params[:event][:group].join(',')
      else
        e[:group] = nil
      end
    end
  end

  def school_first_ranks(school_id, event_ids, group)
    event_ranks = Team.find_by_sql("select GROUP_CONCAT(rank) as ranks from teams where school_id = #{school_id} and teams.group in #{group} and event_id in #{'('+event_ids+')'} GROUP BY teams.event_id")
    round_ranks = 0
    ranks = []
    event_ranks.each_with_index do |er, index|
      rank_num = er.ranks.to_s.split(',').sort[0].to_i
      round_ranks += (rank_num == 0 ? 100 : rank_num)
      ranks << rank_num
    end
    [round_ranks, ranks.join(',')]
  end
end
