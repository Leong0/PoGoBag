module SessionsHelper
  require 'poke-api'

  def current_user
    if (name = session[:pogo_alias])
      @current_user ||= User.find_by(name: name)
    end
  end

  def logged_in?
    !current_user.nil?
  end

  def log_out
    session.delete(:pogo_alias)
    session.delete(:user)
    @user = nil
  end

  # Reset database
  def destroy_user_data(user)
    user.pokemon.where(user_id: user.id).delete_all
    user.items.where(user_id: user.id).delete_all
  end

  # Parse through all data and store into database
  def store_data(client, user)
    call = get_call(client, :get_inventory)
    while call.response[:status_code] != 1
      logger.debug "GET_INVENTORY yielded nil response...Calling again"
      call = get_call(client, :get_inventory)
    end
    response = call.response
    file = File.read('app/assets/pokemon.en.json')
    pokemon_hash = JSON.parse(file)

    #begin
    response[:GET_INVENTORY][:inventory_delta][:inventory_items].each do |item|
      item[:inventory_item_data].each do |type, i|
        if i != nil
          case type
          when :player_stats
            user.level = i[:level]
            user.experience = i[:experience]
            user.prev_level_xp = i[:prev_level_xp]
            user.next_level_xp = i[:next_level_xp]
            user.pokemons_encountered = i[:pokemons_encountered]
            user.km_walked = i[:km_walked]
            user.pokemons_captured = i[:pokemons_captured]
            user.poke_stop_visits = i[:poke_stop_visits]
            user.pokeballs_thrown = i[:pokeballs_thrown]
            user.battle_attack_won = i[:battle_attack_won]
            user.battle_attack_total = i[:battle_attack_total]
            user.battle_defended_won = i[:battle_defended_won]
            user.prestige_rasied_total = i[:prestige_rasied_total]
            user.save
          when :item 
            item_id = i[:item_id]
            count = i[:count]
            user.items.create(item_id: item_id, count: count)
          when :pokemon_data
            # Set poke_id
            poke_id = i[:pokemon_id].capitalize.to_s
            # To deal with Nidoran naming
            poke_id.match('Nidoran_female') ? poke_id = 'Nidoran♀' : nil
            poke_id.match('Nidoran_male') ? poke_id = 'Nidoran♂' : nil

            # To deal with MISSINGNO Pokemon
            if pokemon_hash.key(poke_id) != nil
              poke_num = pokemon_hash.key(poke_id)
            else
              poke_num = "0"
            end

            # Instantiate pokemon
            pokemon = user.pokemon.new
            # Set data
            pokemon.poke_id = poke_id
            pokemon.poke_num = poke_num
            pokemon.move_1 = i[:move_1]
            pokemon.move_2 = i[:move_2]
            pokemon.health = i[:stamina]
            pokemon.max_health = i[:stamina_max]
            pokemon.attack = i[:individual_attack]
            pokemon.defense = i[:individual_defense]
            pokemon.stamina = i[:individual_stamina]
            pokemon.cp = i[:cp]
            pokemon.iv = ((pokemon.attack + pokemon.defense + pokemon.stamina) / 45.0).round(2)
            pokemon.nickname = i[:nickname]
            pokemon.favorite = i[:favorite]
            pokemon.num_upgrades = i[:num_upgrades]
            pokemon.battles_attacked = i[:battles_attacked]
            pokemon.battles_defended = i[:battles_defended]
            pokemon.pokeball = i[:pokeball]
            pokemon.height_m = i[:height_m]
            pokemon.weight_kg = i[:weight_kg]
            # Save record
            pokemon.save
          end
        end
      end
    end
    # Cleanup error pokemonn (Actually eggs)
    Pokemon.where(poke_id: "Missingno").delete_all
    return true
  end

  # get name from logged in client
  def get_name(client)
    call = get_call(client, :get_player)
    name = call.response[:GET_PLAYER][:player_data][:username]
  end

  # Handle login logic
  def setup_client(client)
    if params.has_key? :ptc # PTC LOGIN------------
      # Grab all credentials from form
      username = params[:ptc][:username]
      pass = params[:ptc][:password]
      client.login(username, pass, 'ptc')
      return client
    end
    if params.has_key? :google # GOOGLE LOGIN---------
      clnt = HTTPClient.new
      body = {
        grant_type: 'authorization_code',
        redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
        scope: 'openid email https://www.googleapis.com/auth/userinfo.email',
        client_secret: 'NCjF1TLi2CcY6t5mt0ZveuL7',
        client_id: '848232511240-73ri3t7plvk96pj4f85uj8otdat2alem.apps.googleusercontent.com',
        code: params[:google][:code],
      }
      uri = 'https://accounts.google.com/o/oauth2/token'
      response = clnt.post(uri, body)
      body = response.body
      hash = JSON.parse body
      token = hash["id_token"]
      client = Poke::API::Client.new
      google = Poke::API::Auth::GOOGLE.new("username", "password")
      google.instance_variable_set(:@access_token, token)
      client.instance_variable_set(:@auth, google)
      client.instance_eval { fetch_endpoint }
      return client
    end
  end 

  # get response from call by providing client and request
  def get_call(client, req)
    client.send req
    call = client.call
  end

end
