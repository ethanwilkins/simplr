class ProposalsController < ApplicationController
  before_action :set_proposal, only: [:old_versions, :show, :show_modal, :edit, :update, :destroy, :open_menu, :close_menu, :add_photoset, :hide]
  before_action :unable_to_edit, only: [:edit, :update, :destroy]
  before_action :set_at_anrcho

  before_action :dev_only, only: [:hide]

  def open_menu
    @proposal_shown = params[:showing]
  end

  def show_modal
    run_for_show
  end

  def add_form
    @group = Group.find_by_id params[:group_id]
    @proposal = if @group then @group.proposals.new else Proposal.new end
    @post = if @group then @group.posts.new else Post.new end
  end

  def hide
    @proposal.update hidden: true
  end

  def hide_anrcho_info
    cookies.permanent[:hide_anrcho_info] = true
  end

  def old_versions
    @old_versions = @proposal.old_versions
  end

  def load_section_links
    @group = Group.find_by_token(params[:group_token])
  end

  def index
    cookies[:at_anrcho] = cookies[:anrcho] = "true" if anrcho?
    @proposal = Proposal.new
    @showing_motions = true
    build_feed :main
  end

  def update
    if @proposal.update(proposal_params)
      if params[:pictures]
        params[:pictures][:image].each do |image|
          @proposal.pictures.create image: image
        end
        # adds order numbers to each picture in photoset if more than 1 now
        @proposal.pictures.first.ensure_order if @proposal.pictures.present? and @proposal.pictures.size > 1
      end
      Tag.extract @proposal
      redirect_to edit_proposal_path(@proposal.unique_token), notice: "Successfully updated motion."
    else
      flash.now[:notice] = "Could not successfully update motion."
      render :edit
    end
  end

  def new
    @proposal = Proposal.new
    @parent_proposal = Proposal.find_by_id(params[:proposal_id])
    @group = Group.find_by_id(params[:group_id])
  end

  def create
    @proposal = Proposal.new(proposal_params)
    @proposal.user_id = current_user.id if current_user
    @proposal.group_id = params[:group_id]
    @proposal.anon_token = anon_token

    if @proposal.action.eql? "grant_title"

    end

    build_action
    if @proposal.save
      if params[:pictures]
        # builds photoset for motion
        params[:pictures][:image].each do |image|
          @proposal.pictures.create image: image
        end
        # adds order numbers to each picture in photoset if more than 1
        @proposal.pictures.first.ensure_order if @proposal.pictures.present? and @proposal.pictures.size > 1
      end
      Tag.extract @proposal
      # checks for users mention and notifys each mentioned user
      user_mentioned? @proposal
      if @proposal.proposal
        Note.notify :revision_submitted, @proposal.proposal.unique_token
        redirect_to show_proposal_path(token: @proposal.proposal.unique_token, revisions: true)
      elsif @proposal.group
        redirect_to show_group_path(@proposal.group.unique_token)
      else
        redirect_to proposals_path
      end
    else
      redirect_to proposals_path
    end
  end

  def show
    @group = @proposal.group if @proposal
    if @proposal
      run_for_show
    else
      redirect_to '/404'
    end
  end

  def destroy
    @proposal.destroy
    redirect_to root_url unless str_to_bool params[:ajax_req]
  end

  # Proposal sections: :voting, :revision, :ratified
  def switch_section
    @group = Group.find_by_unique_token params[:group_token]
    @section = params[:section]
    build_feed @section, @group
  end

  # Sub sections: :votes, :comments
  def switch_sub_section
    redirect_to show_proposal_path(@proposal.unique_token)
  end

  private

  def run_for_show
    @proposal_shown = true
    seent @proposal

    # gets all votes for and against
    @up_votes = @proposal.up_votes
    @down_votes = @proposal.down_votes
    @abstains = @proposal.abstains
    @votes = @proposal.votes

    for vote in @votes
      seent vote
    end

    # gets all comments/discussion
    @comments = @proposal.comments
    @comment = Comment.new

    # gets any revisions to proposal
    @revisions = @proposal.proposals
    @revision = Proposal.new

    # gets views, viewed by users other than current users
    @views = if current_user
      @proposal.views.where.not user_id: current_user.id
    else
      @proposal.views
    end
    # filters any views by the OP, of course they saw, they posted it
    @views = @views.where.not(user_id: @proposal.user_id) if @proposal.user_id
    # gets any likes for the motion
    @likes = @proposal.likes

    @old_versions = @proposal.old_versions

    @show_proposal_sub_type = :votes
    if params[:revisions] and @proposal.requires_revision
      @show_proposal_sub_type = :revisions
    elsif params[:comments] or (@votes.empty? and @comments.present?)
      @show_proposal_sub_type = :comments
    end

    @proposal.evaluate
  end

  def set_at_anrcho
    @anrcho = true if anrcho?
  end

  def unable_to_edit
    redirect_to '/404' unless @proposal.able_to_edit? or dev?
  end

  def bots_to_404
    redirect_to '/404' if request.bot?
  end

  def dev_only
    unless dev?
      redirect_to '/404'
    end
  end

  def invite_only
    unless invited?
      redirect_to invite_only_path
    end
  end

  def set_proposal
    if params[:token]
      @proposal = Proposal.find_by_unique_token(params[:token])
      @proposal ||= Proposal.find_by_id(params[:token])
    else
      @proposal = Proposal.find_by_unique_token(params[:id])
      @proposal ||= Proposal.find_by_id(params[:id])
    end
    redirect_to '/404' unless @proposal
  end

  def build_feed section, group=nil
    build_proposal_feed section, group
  end

  def build_action
    action = params[:proposal][:action]
    action = params[:proposal_action] unless action.present?
    case (action.present? ? action : "").to_sym
    when :revision
      old_proposal = Proposal.find params[:proposal_id]
      @proposal.action = "revision"
      # revision belongs to motion that it's revising
      @proposal.proposal_id = old_proposal.id
      # also in the same group if present
      @proposal.group_id = old_proposal.group_id
      # still keeps original or updated action in different field
      @proposal.revised_action = params[:revised_action]
      # where versioning happens, gets blocked proposals version + 1, when a revision
      @proposal.version = old_proposal.version.to_i + 1
    when :grant_title
      grant = {title: nil, days_alive: nil}
      grant[:title] = params[:title]
      grant[:days_alive] = params[:days_alive]
      @proposal.misc_data = grant.to_s
    when :update_name
    end
  end

  def proposal_params
    params[:proposal].permit(:title, :body, :action, :image, :misc_data, :anrcho_only, pictures_attributes: [:id, :proposal_id, :image])
  end
end
