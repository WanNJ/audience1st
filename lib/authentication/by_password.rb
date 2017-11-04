module Authentication
  module ByPassword
    require 'digest/sha1'
    require 'bcrypt'

    # Stuff directives into including module
    def self.included(recipient)
      recipient.extend(ModelClassMethods)
      recipient.class_eval do
        include ModelInstanceMethods
        
        # Virtual attribute for the unencrypted password
        attr_accessor :password
        # validates_presence_of     :password,                   :if => :password_required?
        # validates_presence_of     :password_confirmation,      :if => :password_required?
        # validates_confirmation_of :password,                   :if => :password_required?
        # validates_length_of       :password, :within => 6..40, :if => :password_required?
        before_save :encrypt_password
      end
    end # #included directives

    #
    # Class Methods
    #
    module ModelClassMethods
      # This provides a modest increased defense against a dictionary attack if
      # your db were ever compromised, but will invalidate existing passwords.
      # See the README and the file config/initializers/site_keys.rb
      #
      # It may not be obvious, but if you set REST_AUTH_SITE_KEY to nil and
      # REST_AUTH_DIGEST_STRETCHES to 1 you'll have backwards compatibility with
      # older versions of restful-authentication.
      def password_digest(password, salt)
        Digest::SHA1.hexdigest(password.strip.to_s+salt.to_s)
        # digest = REST_AUTH_SITE_KEY
        # REST_AUTH_DIGEST_STRETCHES.times do
        #   digest = secure_digest(digest, salt, password, REST_AUTH_SITE_KEY)
        # end
        # digest
      end      
    end # class methods

    #
    # Instance Methods
    #
    module ModelInstanceMethods
      
      # Encrypts the password with the user salt
      def encrypt(password)
        self.class.password_digest(password, salt)
      end
      
      def authenticated?(password)
         bcrypted? ? BCrypt::Password.new(bcrypted_password) == password : crypted_password == encrypt(password)
      end
      
      # before filter 
      def encrypt_password
        # allow using update_attribute to save crypted_password directly if it
        # has been changed. Otherwise the before_save will clobber it.
        return if (password.blank? ||  crypted_password_changed?)
        # self.salt = self.class.make_token if new_record?
        # self.crypted_password = encrypt(password)
        bcrypt_password_storage(password)
      end

      def password_required?
        crypted_password.blank? || !password.blank?
      end

      def bcrypt_password_storage(password)
        self.bcrypted_password = BCrypt::Password.create(password).to_s
        self.crypted_password = nil
      end

      def bcrypted?
        return self.crypted_password.nil? && !!self.bcrypted_password
      end

    end # instance methods
  end
end
