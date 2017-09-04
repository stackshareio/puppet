require 'spec_helper'
require 'puppet_spec/files'
require 'puppet_spec/compiler'

require 'puppet/pops'
require 'puppet/loaders'

module Puppet::Pops
module Loader
describe 'The Loader' do
  include PuppetSpec::Compiler
  include PuppetSpec::Files

  let(:testing_env) do
    {
      'testing' => {
        'functions' => functions,
        'lib' => { 'puppet' => lib_puppet },
        'manifests' => manifests,
        'modules' => modules,
        'plans' => plans,
        'tasks' => tasks,
        'types' => types,
      }
    }
  end

  let(:functions) { {} }
  let(:manifests) { {} }
  let(:modules) { {} }
  let(:plans) { {} }
  let(:lib_puppet) { {} }
  let(:tasks) { {} }
  let(:types) { {} }

  let(:environments_dir) { Puppet[:environmentpath] }

  let(:testing_env_dir) do
    dir_contained_in(environments_dir, testing_env)
    env_dir = File.join(environments_dir, 'testing')
    PuppetSpec::Files.record_tmp(env_dir)
    env_dir
  end

  let(:modules_dir) { File.join(testing_env_dir, 'modules') }
  let(:env) { Puppet::Node::Environment.create(:testing, [modules_dir]) }
  let(:node) { Puppet::Node.new('test', :environment => env) }
  let(:loader) { Loaders.find_loader(nil) }

  before(:each) { Puppet.push_context(:loaders => Loaders.new(env)) }
  after(:each) { Puppet.pop_context }

  context 'when doing discovery' do
    context 'of things' do
      it 'finds statically basic types' do
        expect(loader.discover(:type)).to include(tn(:type, 'integer'))
      end

      it 'finds statically loaded types' do
        expect(loader.discover(:type)).to include(tn(:type, 'file'))
      end

      it 'finds statically loaded Object types' do
        expect(loader.discover(:type)).to include(tn(:type, 'puppet::ast::accessexpression'))
      end

      context 'in environment' do
        let(:types) {
          {
            'global.pp' => <<-PUPPET.unindent,
              type Global = Integer
              PUPPET
            'environment' => {
              'env.pp' => <<-PUPPET.unindent,
                type Environment::Env = String
                PUPPET
            }
          }
        }

        let(:tasks) {
          {
            'globtask' => '',
            'environment' => {
              'envtask' => ''
            }
          }
        }

        let(:functions) {
          {
            'globfunc.pp' => 'function globfunc() {}',
            'environment' => {
              'envfunc.pp' => 'function environment::envfunc() {}'
            }
          }
        }

        let(:lib_puppet) {
          {
            'functions' => {
              'globrubyfunc.rb' => 'Puppet::Functions.create_function(:globrubyfunc) { def globrubyfunc; end }',
              'environment' => {
                'envrubyfunc.rb' => "Puppet::Functions.create_function(:'environment::envrubyfunc') { def envrubyfunc; end }",
              }
            }
          }
        }

        it 'finds global types in environment' do
          expect(loader.discover(:type)).to include(tn(:type, 'global'))
        end

        it 'finds global functions in environment' do
          expect(loader.discover(:function)).to include(tn(:function, 'lookup'))
        end

        it 'finds types prefixed with Environment in environment' do
          expect(loader.discover(:type)).to include(tn(:type, 'environment::env'))
        end

        it 'finds global tasks in environment' do
          expect(loader.discover(:type)).to include(tn(:type, 'globtask'))
        end

        it 'finds tasks prefixed with Environment in environment' do
          expect(loader.discover(:type)).to include(tn(:type, 'environment::envtask'))
        end

        it 'finds global functions in environment' do
          expect(loader.discover(:function)).to include(tn(:function, 'globfunc'))
        end

        it 'finds functions prefixed with Environment in environment' do
          expect(loader.discover(:function)).to include(tn(:function, 'environment::envfunc'))
        end

        it 'finds global ruby functions in environment' do
          expect(loader.discover(:function)).to include(tn(:function, 'globrubyfunc'))
        end

        it 'finds ruby functions prefixed with Environment in environment' do
          expect(loader.discover(:function)).to include(tn(:function, 'environment::envrubyfunc'))
        end

        it 'can filter the list of discovered entries using a block' do
          expect(loader.discover(:function) { |t| t.name =~ /rubyfunc\z/ }).to contain_exactly(
            tn(:function, 'environment::envrubyfunc'),
            tn(:function, 'globrubyfunc')
          )
        end

        context 'with multiple modules' do
          let(:metadata_json_a) {
              {
                'name': 'example/a',
                'version': '0.1.0',
                'source': 'git@github.com/example/example-a.git',
                'dependencies': [{'name' => 'c', 'version_range' => '>=0.1.0'}],
                'author': 'Bob the Builder',
                'license': 'Apache-2.0'
              }
          }

          let(:metadata_json_b) {
            {
              'name': 'example/b',
              'version': '0.1.0',
              'source': 'git@github.com/example/example-b.git',
              'dependencies': [{'name' => 'c', 'version_range' => '>=0.1.0'}],
              'author': 'Bob the Builder',
              'license': 'Apache-2.0'
            }
          }

          let(:metadata_json_c) {
            {
              'name': 'example/c',
              'version': '0.1.0',
              'source': 'git@github.com/example/example-c.git',
              'dependencies': [],
              'author': 'Bob the Builder',
              'license': 'Apache-2.0'
            }
          }

          let(:modules) {
            {
              'a' => {
                'functions' => a_functions,
                'lib' => { 'puppet' => a_lib_puppet },
                'plans' => a_plans,
                'tasks' => a_tasks,
                'types' => a_types,
                'metadata.json' => metadata_json_a.to_json
              },
              'b' => {
                'functions' => b_functions,
                'lib' => { 'puppet' => b_lib_puppet },
                'plans' => b_plans,
                'tasks' => b_tasks,
                'types' => b_types,
                'metadata.json' => metadata_json_b.to_json
              },
              'c' => {
                'types' => c_types,
                'metadata.json' => metadata_json_c.to_json
              },
            }
          }

          let(:a_plans) {
            {
              'aplan.pp' => <<-PUPPET.unindent,
                plan a::aplan() {}
                PUPPET
            }
          }

          let(:a_types) {
            {
              'atype.pp' => <<-PUPPET.unindent,
                type A::Atype = Integer
                PUPPET
            }
          }

          let(:a_tasks) {
            {
              'atask' => '',
            }
          }

          let(:a_functions) {
            {
              'afunc.pp' => 'function a::afunc() {}',
            }
          }

          let(:a_lib_puppet) {
            {
              'functions' => {
                'a' => {
                  'arubyfunc.rb' => "Puppet::Functions.create_function(:'a::arubyfunc') { def arubyfunc; end }",
                }
              }
            }
          }

          let(:b_plans) {
            {
              'aplan.pp' => <<-PUPPET.unindent,
                plan b::aplan() {}
                PUPPET
            }
          }

          let(:b_types) {
            {
              'atype.pp' => <<-PUPPET.unindent,
                type B::Atype = Integer
                PUPPET
            }
          }

          let(:b_tasks) {
            {
              'atask' => '',
            }
          }

          let(:b_functions) {
            {
              'afunc.pp' => 'function b::afunc() {}',
            }
          }

          let(:b_lib_puppet) {
            {
              'functions' => {
                'b' => {
                  'arubyfunc.rb' => "Puppet::Functions.create_function(:'b::arubyfunc') { def arubyfunc; end }",
                }
              }
            }
          }

          let(:c_types) {
            {
              'atype.pp' => <<-PUPPET.unindent,
                type C::Atype = Integer
            PUPPET
            }
          }

          it 'private loader finds plans in all modules' do
            expect(loader.private_loader.discover(:plan) { |t| t.name =~ /^.::.*\z/ }).to(
              contain_exactly(tn(:plan, 'a::aplan'), tn(:plan, 'b::aplan')))
          end

          it 'module loader finds plans only in itself' do
            expect(Loaders.find_loader('a').discover(:plan)).to(
              contain_exactly(tn(:plan, 'a::aplan')))
          end

          it 'private loader finds types in all modules' do
            expect(loader.private_loader.discover(:type) { |t| t.name =~ /^.::.*\z/ }).to(
              contain_exactly(tn(:type, 'a::atype'), tn(:type, 'b::atype'), tn(:type, 'c::atype'), tn(:type, 'a::atask'), tn(:type, 'b::atask')))
          end

          it 'module loader finds types only in itself' do
            expect(Loaders.find_loader('a').discover(:type) { |t| t.name =~ /^.::.*\z/ }).to(
              contain_exactly(tn(:type, 'a::atype'), tn(:type, 'a::atask')))
          end

          it 'private loader finds functions in all modules' do
            expect(loader.private_loader.discover(:function) { |t| t.name =~ /^.::.*\z/ }).to(
              contain_exactly(tn(:function, 'a::afunc'), tn(:function, 'b::afunc'), tn(:function, 'a::arubyfunc'), tn(:function, 'b::arubyfunc')))
          end

          it 'module loader finds functions only in itself' do
            expect(Loaders.find_loader('a').discover(:function) { |t| t.name =~ /^.::.*\z/ }).to(
              contain_exactly(tn(:function, 'a::afunc'), tn(:function, 'a::arubyfunc')))
          end

          it 'discover is only called once on dependent loader' do
            ModuleLoaders::FileBased.any_instance.expects(:discover).times(4).with(:type, Pcore::RUNTIME_NAME_AUTHORITY).returns([])
            expect(loader.private_loader.discover(:type) { |t| t.name =~ /^.::.*\z/ }).to(contain_exactly())
          end

          context 'with no explicit dependencies' do

            let(:modules) {
              {
                'a' => {
                  'functions' => a_functions,
                  'lib' => { 'puppet' => a_lib_puppet },
                  'plans' => a_plans,
                  'tasks' => a_tasks,
                  'types' => a_types,
                },
                'b' => {
                  'functions' => b_functions,
                  'lib' => { 'puppet' => b_lib_puppet },
                  'plans' => b_plans,
                  'tasks' => b_tasks,
                  'types' => b_types,
                },
                'c' => {
                  'types' => c_types,
                },
              }

              it 'discover is only called once on dependent loader' do
                ModuleLoaders::FileBased.any_instance.expects(:discover).times(4).with(:type, Pcore::RUNTIME_NAME_AUTHORITY).returns([])
                expect(loader.private_loader.discover(:type) { |t| t.name =~ /^.::.*\z/ }).to(contain_exactly())
              end
            }
          end
        end
      end
    end
  end

  def tn(type, name)
    TypedName.new(type, name)
  end
end
end
end
