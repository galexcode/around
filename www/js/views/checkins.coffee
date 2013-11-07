define ['zepto', 'underscore', 'backbone', 'cs!collections/checkins', 'cs!collections/users', 'cs!collections/venues', 'cs!models/checkin', 'tpl!templates/checkins/create-from-venues.html.ejs', 'tpl!templates/checkins/insight.html.ejs', 'tpl!templates/checkins/show.html.ejs', 'tpl!templates/full-modal.html.ejs'], ($, _, Backbone, Checkins, Users, Venues, Checkin, CreateFromVenuesTemplate, InsightTemplate, ShowTemplate, FullModalTemplate) ->
  'use strict'

  # View to create a check-in for a user. Pass a user and a venue object in
  # and we create a new check-in.
  CreateView = Backbone.View.extend
    initialize: (venue, user = null) ->
      user = Users.getSelf() unless user

      self = this

      $.when(user.checkIn venue).done (checkin) ->
        # Navigate to the venue page first, then load our insight modal.
        # TODO: This shouldn't be part of state; load it in as a special
        # modal view instead?
        window.router.navigate "/venues/#{checkin.get('venue').id}",
          replace: true
          trigger: true

        $('#modal').show()
        new InsightModalView
          id: checkin.get('id')

  InsightModalView = Backbone.View.extend
    el: '#modal'
    $el: $('#modal')
    model: Checkin
    template: InsightTemplate

    events:
      "click #modal": "goToVenue"
      "click .accept": "goToVenue"

    initialize: ->
      self = this

      Checkins.get @id,
        success: (checkin) ->
          self.model = checkin
          self.render()
        error: (response) ->
          # If there was an error, we should abandon ship and head to the index
          # page.
          window.router.navigate "",
            replace: true
            trigger: true

    render: ->
      html = @template
        checkin: @model

      $(@$el).html(html)

    goToVenue: ->
      $('#modal').hide()
      window.router.navigate "venues/#{@model.get('venue').id}",
        replace: true
        trigger: true

  # View to create a check-in from a list of venues. This is the view that
  # appears when the user taps the "check in" button at the bottom of the
  # screen.
  ModalFromVenuesView = Backbone.View.extend
    headerLocation: null
    map: null
    position: null
    template: CreateFromVenuesTemplate
    user: null
    venues: []

    _cancelMap: false

    events:
      "click .venue": "checkInToVenue"

    # Get the relevant local venues for this user while we render the template.
    initialize: ->
      _.bindAll this # "render", "showMap", "_geoSuccess"

      window.navigator.geolocation.getCurrentPosition(
        @_geoSuccess, @_geoError
      )

      $('body').append FullModalTemplate {
        element: @options._el
        fixedContent: '<div id="map"></div>'
        templateHTML: @template(@_templateData())
      }

      @setElement @options._el

      @render()

    render: ->
      html = @template(@_templateData())

      $(@$el).html(html)

      if @position
        self = this

        if @venues.length
          # Create bounds for the map to focus on.
          bounds = new L.Bounds()

          # Add the top five venues to the map.
          _.first(@venues, 4).forEach (v) ->
            L.marker([v.location.lat, v.location.lng]).addTo(self.map)
            bounds.extend [v.location.lat, v.location.lng]

          latLngBounds = new L.LatLngBounds([
            [bounds.min.x, bounds.min.y],
            [bounds.max.x, bounds.max.y]
          ])
          @map.fitBounds(latLngBounds, {
            padding: [25, 25]
          })

    checkInToVenue: (event) ->
      window.app.destroyFullModal()

      window.router.navigate "checkins/create/#{$(event.currentTarget).data('venue')}",
        replace: false
        trigger: true

    showMap: ->
      @map = L.mapbox.map('map', window.GLOBALS.MAP_ID, {
        zoomControl: false
      }).setView([@position.coords.latitude, @position.coords.longitude], 14)

      # Disable drag and zoom handlers
      @map.dragging.disable()
      @map.touchZoom.disable()
      @map.doubleClickZoom.disable()
      @map.scrollWheelZoom.disable()
      # Disable tap handler, if present.
      @map.tap.disable() if @map.tap

    _geoSuccess: (position) ->
      self = this

      @position = position

      @showMap()

      Venues.near
        ll: "#{@position.coords.latitude},#{@position.coords.longitude}"
        accuracy: @position.coords.accuracy
      .done (apiResponse) ->
        response = apiResponse.response
        _(response.groups[0].items).each (item) ->
          self.venues.push item.venue

        self.headerLocation = response.headerFullLocation

        self.render()
      .fail ->
        window.alert "Error getting venues!"

      @render()

    _geoError: ->
      return

    _cleanUpMap: ->
      @_cancelMap = true
      @map.remove()

    _templateData: ->
      {
        headerLocation: @headerLocation
        position: @position
        venues: @venues
      }

  ShowView = Backbone.View.extend
    template: ShowTemplate

  return {
    Create: CreateView
    InsightModal: InsightModalView
    ModalFromVenues: ModalFromVenuesView
  }