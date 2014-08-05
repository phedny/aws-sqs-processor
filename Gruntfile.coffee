module.exports = ->

	pkg = @file.readJSON 'package.json'

	@initConfig
		clean:
			src: ['lib', 'reports']
		copy:
			js:
				cwd: 'src'
				expand: true
				src: ['**/*.js']
				dest: 'lib'
		mkdir:
			lib:
				options:
					create: ['lib']
			reports:
				options:
					create: ['reports']
		coffee:
			build:
				options:
					bare: true
				expand: true
				cwd: 'src'
				src: ['**/*.coffee']
				dest: 'lib'
				ext: '.js'
		mochaTest:
			test:
				options:
					require: 'coffee-script/register'
					reporter: 'spec'
				src: ['test/**/*.coffee']
			jenkins:
				options:
					require: 'coffee-script/register'
					reporter: 'xunit'
					quiet: true
					captureFile: 'reports/test-result.xml'
				src: ['test/**/*.coffee']

	@loadNpmTasks 'grunt-contrib-clean'
	@loadNpmTasks 'grunt-contrib-coffee'
	@loadNpmTasks 'grunt-contrib-copy'
	@loadNpmTasks 'grunt-mkdir'
	@loadNpmTasks 'grunt-mocha-test'

	@registerTask 'test', ['mochaTest:test']
	@registerTask 'build', ['mkdir:lib', 'coffee', 'copy:js']
	@registerTask 'default', ['clean', 'test', 'build']
	@registerTask 'jenkins', ['clean', 'mkdir:reports', 'mochaTest:jenkins', 'build']