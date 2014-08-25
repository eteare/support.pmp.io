class PasswordResetController < ApplicationController

  before_filter :setup_negative_captcha
  before_filter :require_not_login!

  # GET /forgot
  def new
  end

  # POST /forgot
  def create
    if @captcha.valid?
      collection = find_all_by_auth_user(@captcha.values)
      if collection.items.count == 1
        if email = get_contact_email(collection.items.first)
          reset_params = {
            email_address: email,
            user_name: @captcha.values[:username],
            user_guid: collection.items.first.guid,
            host: @captcha.values[:host],
          }
          if PasswordReset.create(reset_params)
            ga_event!('passwords', 'create')
            redirect_to login_path, notice: "An email with reset instructions has been sent to #{email}.  If this is incorrect, please #{support_mailto}."
          else
            flash.now.alert = "Something went wrong - please #{support_mailto}."
            ga_event!('passwords', 'fatal')
            render :new
          end
        else
          ga_event!('passwords', 'no_email')
          redirect_to login_path, alert: "No email associated with user - please #{support_mailto}."
        end
      elsif collection.items.count < 1
        flash.now.alert = 'Unable to find a user by that name'
        ga_event!('passwords', 'no_name')
        render :new
      else
        flash.now.alert = 'Error: too many users with that name!'
        ga_event!('passwords', 'too_many')
        render :new
      end
    else
      flash.now.alert = @captcha.error
      ga_event!('passwords', 'captcha')
      render :new
    end
  end

  # GET /forgot/1234
  def show
    @reset = PasswordReset.find_by!(token: params[:id])
    if 14.days.ago > @reset.created_at
      @reset.destroy
      redirect_to forgot_path, notice: 'Sorry - that link has expired.  Please request another.'
    end
  end

  # PUT /forgot/1234
  def update
    @reset = PasswordReset.find_by!(token: params[:id])
    if @captcha.valid?
      if @captcha.values['username'] != @reset.user_name
        flash.now.alert = 'Incorrect username provided'
        ga_event!('passwords', 'non_match')
        render :show
      elsif @captcha.values['password'] != @captcha.values['confirm_password']
        flash.now.alert = 'Password does not match confirmation'
        ga_event!('passwords', 'confirmation')
        render :show
      elsif !password_valid?(@reset.user_name, @captcha.values['password'])
        flash.now.alert = 'Your password is weak!  Beef it up a bit, eh?'
        ga_event!('passwords', 'weak')
        render :show
      else
        doc = find_by_reset(@reset)
        doc.auth[:password] = @captcha.values['password']
        doc.save
        @reset.destroy
        ga_event!('passwords', 'success')
        redirect_to login_path, notice: 'Password changed!  Please login.'
      end
    else
      flash.now.alert = @captcha.error
      ga_event!('passwords', 'captcha')
      render :show
    end
  end

protected

  # negative-captcha gem
  def setup_negative_captcha
    @captcha = NegativeCaptcha.new(
      secret:  Rails.application.secrets.secret_key_base,
      spinner: request.remote_ip,
      fields: [:host, :username, :password, :confirm_password],
      params: params
    )
  end

  # lookup users TODO: this query param not exposed yet
  def find_all_by_auth_user(values)
    pmp = admin_pmp(values[:host])
    href = "#{pmp.endpoint}/users?auth_user=" + CGI::escape(values[:username])
    PMP::CollectionDocument.new(pmp.options.merge(href: href, root: pmp.root))
  end

  # find user from a password reset model
  def find_by_reset(reset)
    pmp = admin_pmp(reset.host)
    href = "#{pmp.endpoint}/docs/#{reset.user_guid}"
    PMP::CollectionDocument.new(pmp.options.merge(href: href, root: pmp.root))
  end

  # link to support
  def support_mailto
    "<a href='mailto:support@publicmediaplatform.org'>contact support</a>"
  end

  # check password strength
  def password_valid?(uname, pwd)
    strength = PasswordStrength.test(uname, pwd)
    strength.valid?(:good)
  end

  def get_contact_email(doc)
    if doc.emails.present?
      eml = doc.emails.find { |e| e['type'] == 'primary' } || docs.emails.first
      eml['email']
    else
      doc.email
    end
  end

end
