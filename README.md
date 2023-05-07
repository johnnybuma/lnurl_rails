# Rails 7 Boilerplate App

This is a boilerplate Rails 7 application using bootstrap 5 for styling and devise for authentication.

To get started in development begin with the following:
* Install ruby 3.0.0 and create a project gemset called rails7
```
rvm use 3.0.0@rails7 --create
```

* Install all dependencies

```
bundle install
yarn install
rails generate devise:install
```

* Set-up database
```
rails db:setup

rails db:migrate
```

* Start application

```
./bin/dev
```
