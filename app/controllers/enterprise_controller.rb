# Manage enterprises by providing an interface to register, activate and manage them
class EnterpriseController < ApplicationController

  def index
    @my_enterprises = current_user.enterprises if current_user
    @enterprises = Enterprise.find(:all) - @my_enterprises
  end
  
  def register
    unless logged_in?
      redirect_to :controller => 'account'
    end
  end

  def register_form
    @vitual_communities = VirtualCommunity.find(:all)
  end

  def choose_validation_entity_or_net
    @enterprise = Enterprise.new(params[:enterprise])
  end

  def create
    @enterprise = Enterprise.new(params[:enterprise])
    @enterprise.manager = current_user
    if @enterprise.save
      flash[:notice] = _('Enterprise was succesfully created')
      redirect_to :action => 'register'
    else
      flash[:notice] = _('Enterprise was not created')
      render :action => 'choose_validation_entity_or_net'
    end
  end
end
