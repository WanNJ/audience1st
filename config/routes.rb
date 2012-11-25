ActionController::Routing::Routes.draw do |map|
  map.resources :bulk_downloads
  map.resources :account_codes
  map.resources :imports
  map.resources :labels
  
  # just enough RESTful routes for restful_authentication to work
  # map.resources :customers
  map.connect '/customers/:id/show', :controller => 'customers', :action => 'welcome'

  map.connect '/store/donate/:fund', :controller => 'store', :action => 'donate'

  # special shortcuts
  map.login '/login', :controller => 'sessions', :action => 'new'
  map.forgot_password '/customers/forgot_password', :controller => 'customers', :action => 'forgot_password'
  map.secret_question '/login_with_secret', :controller => 'sessions', :action => 'new_from_secret_question'
  map.logout '/logout', :controller => 'sessions', :action => 'destroy'
  map.change_user '/not_me', :controller => 'sessions', :action => 'not_me'
  map.store '/store', :controller => 'store', :action => 'index'
  map.home '/customers/welcome', :controller => 'customers', :action => 'welcome'
  map.resource :session # other session actions

  map.connect 'subscribe', :controller => 'store', :action => 'subscribe'

  # Routes for viewing and refunding orders
  map.order '/orders/:id', :controller => 'orders', :action => 'show'
  map.connect '/orders/refund/:id', :controller => 'orders', :action => 'refund'

  # Install the default route as the lowest priority.
  map.connect ':controller/:action/:id'
  map.connect '*anything', :controller => 'customers', :action => 'welcome'
  map.root :controller => 'customers', :action => 'welcome'
 
end
