class ApplicationController < ActionController::Base

  protect_from_forgery with: :exception
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :authenticate_user! # Routes to the login / signup if not authenticated



  @new_room = Room.new



  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username, :phone_number, :avatar])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username, :phone_number, :avatar])
  end


  def authorize_admin
    redirect_back(fallback_location: root_path, alert: "You are not authorized to make that action!") unless current_user.admin?
    #redirects to previous page
  end


end
