module SiteUI.Navigation exposing (adminView, view)

import Category exposing (CategoryId(..))
import Dict
import Html exposing (Html, a, button, div, form, li, node, span, text, ul)
import Html.Attributes exposing (attribute, class, href, id, target, type_)
import Html.Events.Extra exposing (onClickPreventDefault)
import Messages exposing (Msg(..))
import Products.Pagination as Pagination
import RemoteData exposing (WebData)
import Routing exposing (AdminRoute(..), Route(..), reverse)
import Search
import SiteUI exposing (NavigationData)
import SiteUI.Search as SiteSearch
import User exposing (AuthStatus(..))
import Views.Utils exposing (icon, routeLinkAttributes)


view : Route -> AuthStatus -> WebData NavigationData -> List CategoryId -> Search.Data -> Html Msg
view route authStatus navigationData activeCategoryIds searchData =
    let
        categoryNavigation =
            RemoteData.toMaybe navigationData
                |> Maybe.map (\data -> List.map (rootCategory data.children) data.roots)
                |> Maybe.withDefault []

        rootCategory childMap category =
            let
                (CategoryId categoryId) =
                    category.id

                dropdownCategories children =
                    let
                        childItems =
                            List.map childCategory children

                        itemsPerColumn =
                            ceiling <| (toFloat <| List.length childItems) / 3.0

                        splitItems items =
                            [ List.take itemsPerColumn items
                            , List.drop itemsPerColumn items |> List.take itemsPerColumn
                            , List.drop (itemsPerColumn * 2) items
                            ]
                    in
                    if List.length childItems < 15 then
                        childItems

                    else
                        [ div [ class "row no-gutters multi-column-dropdown" ] <|
                            List.map (div [ class "col-12 col-md" ])
                                (splitItems childItems)
                        ]
            in
            case Dict.get categoryId childMap of
                Nothing ->
                    li [ class <| "nav-item" ++ activeClass category ]
                        [ a
                            (class "nav-link"
                                :: (routeLinkAttributes <|
                                        CategoryDetails category.slug Pagination.default
                                   )
                            )
                            [ text category.name ]
                        ]

                Just children ->
                    li [ class <| "nav-item dropdown" ++ activeClass category ]
                        [ a
                            [ class "nav-link dropdown-toggle"
                            , target "_self"
                            , href <|
                                reverse <|
                                    CategoryDetails category.slug Pagination.default
                            , attribute "data-toggle" "dropdown"
                            , attribute "aria-haspopup" "true"
                            , attribute "aria-expanded" "false"
                            ]
                            [ text category.name ]
                        , div [ class "dropdown-menu mt-0" ] <| dropdownCategories children
                        ]

        childCategory category =
            a
                (class ("dropdown-item" ++ activeClass category)
                    :: routeLinkAttributes (CategoryDetails category.slug Pagination.default)
                )
                [ text category.name ]

        mobileOnlyItems =
            [ mobileLink (PageDetails "about-us") "About Us"
            , mobileLink (PageDetails "growing-guides") "Growing Guides"
            , mobileLink (PageDetails "retail-stores") "Retail Stores"
            , mobileLink QuickOrder "Quick Order"
            ]
                ++ authLinks

        authLinks =
            if authStatus == Anonymous then
                [ mobileLink (Login Nothing) "Log In"
                , mobileLink CreateAccount "Register"
                ]

            else
                [ mobileLink MyAccount "My Account"
                , li [ class "nav-item" ]
                    [ a [ href "/account/logout", onClickPreventDefault LogOut ]
                        [ text "Log Out" ]
                    ]
                ]

        mobileLink destination name =
            let
                class_ =
                    if route == destination then
                        "nav-item active d-md-none"

                    else
                        "nav-item d-md-none"
            in
            li
                [ class class_ ]
                [ a (class "nav-link" :: routeLinkAttributes destination)
                    [ text name ]
                ]

        activeClass category =
            if List.member category.id activeCategoryIds then
                " active "

            else
                ""
    in
    div [ id "navigation", class "container" ]
        [ node "nav"
            [ class "navbar navbar-expand-md navbar-light bg-success" ]
            [ a
                (class "ml-auto navbar-toggler" :: routeLinkAttributes Cart)
                [ icon "shopping-cart p-1" ]
            , button
                [ class "navbar-toggler ml-2"
                , type_ "button"
                , attribute "data-toggle" "collapse"
                , attribute "data-target" "#search-navbar"
                , attribute "aria-controls" "navbarSupportedContent"
                , attribute "aria-expanded" "false"
                , attribute "aria-label" "Toggle navigation"
                ]
                [ icon "search p-1" ]
            , button
                [ class "navbar-toggler ml-2"
                , type_ "button"
                , attribute "data-toggle" "collapse"
                , attribute "data-target" "#category-navbar"
                , attribute "aria-controls" "navbarSupportedContent"
                , attribute "aria-expanded" "false"
                , attribute "aria-label" "Toggle navigation"
                ]
                [ span [ class "navbar-toggler-icon" ] [] ]
            , div [ id "search-navbar", class "collapse navbar-collapse" ]
                [ div [ class "mt-2" ] [ SiteSearch.form SearchMsg "light" searchData ]
                , ul [ class "nav navbar-nav" ]
                    [ li [ class "nav-item" ]
                        [ a (class "nav-link" :: routeLinkAttributes AdvancedSearch)
                            [ text "Advanced Search" ]
                        ]
                    ]
                ]
            , div [ id "category-navbar", class "collapse navbar-collapse" ]
                [ ul [ class "navbar-nav mx-auto d-flex text-left" ] <|
                    categoryNavigation
                        ++ mobileOnlyItems
                ]
            ]
        ]


adminView : Route -> Html Msg
adminView route =
    let
        navItem : String -> AdminRoute -> Html Msg
        navItem title targetRoute =
            li [ class <| "nav-item" ++ activeClass targetRoute ]
                [ a
                    (class "nav-link"
                        :: (routeLinkAttributes <| Admin <| targetRoute)
                    )
                    [ text title ]
                ]

        activeClass : AdminRoute -> String
        activeClass targetRoute =
            if Admin targetRoute == route || isChildRoute targetRoute then
                " active "

            else
                ""

        isChildRoute : AdminRoute -> Bool
        isChildRoute parentRoute =
            case route of
                Admin subRoute ->
                    case ( subRoute, parentRoute ) of
                        ( CategoryNew, CategoryList ) ->
                            True

                        ( CategoryNew, _ ) ->
                            False

                        ( CategoryEdit _, CategoryList ) ->
                            True

                        ( CategoryEdit _, _ ) ->
                            False

                        ( CategoryList, _ ) ->
                            False

                        ( PageList, _ ) ->
                            False

                        ( PageNew, PageList ) ->
                            True

                        ( PageNew, _ ) ->
                            False

                _ ->
                    False
    in
    div [ id "navigation", class "admin container-fluid" ]
        [ node "nav"
            [ class "navbar navbar-expand-md navbar-light bg-success" ]
            [ button
                [ class "navbar-toggler ml-2"
                , type_ "button"
                , attribute "data-toggle" "collapse"
                , attribute "data-target" "#admin-navbar"
                , attribute "aria-controls" "navbarSupportedContent"
                , attribute "aria-expanded" "false"
                , attribute "aria-label" "Toggle navigation"
                ]
                [ span [ class "navbar-toggler-icon" ] [] ]
            , div [ id "admin-navbar", class "collapse navbar-collapse" ]
                [ ul [ class "navbar-nav" ]
                    [ navItem "Categories" CategoryList
                    , navItem "Pages" PageList
                    ]
                ]
            ]
        ]
