# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)
include ActionView::Helpers::AssetUrlHelper


#user = CreateAdminService.new.call
#puts 'CREATED ADMIN USER: ' << user.email

User.create(email: "test@mail.com", username: "Johnny", password: 'password', role: 2)


