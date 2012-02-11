#!/usr/bin/ruby -Ku
# encoding: UTF-8
#
#    2010 by ruby.twiddler@gmail.com
#
#      sjis unzip KDE GUI
#

require 'fileutils'

APP_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
APP_NAME = File.basename(APP_FILE).sub(/\.rb/, '')
# APP_DIR = File::dirname(File.expand_path(File.dirname(APP_FILE)))
APP_DIR = File.dirname(File.expand_path(APP_FILE))
LIB_DIR = File.join(APP_DIR, "lib")
APP_VERSION = "0.0.2"


# standard libs
require 'rubygems'
require 'zip/zip'
require 'shellwords'
require 'time'
require 'kconv'
require 'fileutils'

# additional libs
require 'korundum4'
require 'kio'

#
# my libraries and programs
#
$:.unshift(LIB_DIR)
require "mylibs"

#--------------------------------------------------------------------
class OverWriteDlg < KDE::Dialog
    def initialize(parent)
        super(parent)
        setButtons( KDE::Dialog::Yes | KDE::Dialog::No | KDE::Dialog::User1 |
                    KDE::Dialog::User2 | KDE::Dialog::Cancel )
        @textEdit = Qt::Label.new do |w|
            w.wordWrap= true
        end
        self.caption = "over write the file?"
        setButtonText(KDE::Dialog::User2, "Yes to ALL")
        setButtonText(KDE::Dialog::User1, "No to ALL")

        setMainWidget(@textEdit)
    end

    attr_reader :textEdit
    attr_reader :selectedButton

    def self.ask(parent, fileName)
        @@dialog ||= self.new(parent)
        @@dialog.textEdit.text = "#{fileName} is already exist.\nover write this?"
        @@dialog.exec
    end

    # virtual slot
    def slotButtonClicked(btn)
        @selectedButton = btn
        accept
    end

    def self.selectedButton
        @@dialog.selectedButton
    end
end


#--------------------------------------------------------------------
class FileItem
    attr_reader :name, :date, :size, :sjisname
    def initialize(entry)
        @name = entry.name.toutf8
        @size = entry.size
        @date = entry.time
        @sjisname = entry.name
    end
end

class FileTable < Qt::TableWidget
    class Item < Qt::TableWidgetItem
        def initialize(text)
            super(text)
            self.flags = Qt::ItemIsSelectable | Qt::ItemIsEnabled
        end

        def gem
            tableWidget.gem(self)
        end
    end

    def initialize
        super(0, 3)

        setHorizontalHeaderLabels( %w{ Name Date Size } )
        self.horizontalHeader.stretchLastSection = true
        self.selectionBehavior = Qt::AbstractItemView::SelectRows
        self.alternatingRowColors = true

        readSettings
    end

    def setFiles(files)
        clearContents
        @files = []
        self.rowCount = files.size
        files.each_with_index do |f, r|
            @files[r] = f
            setItem(r, 0, Item.new(f.name))
            setItem(r, 1, Item.new(f.date.to_s))
            setItem(r, 2, Item.new(f.size))
        end
    end

    GroupName = "FileTable"
    def writeSettings
        config = $config.group(GroupName)
        config.writeEntry('Header', self.horizontalHeader.saveState)
    end

    def readSettings
        config = $config.group(GroupName)
        self.horizontalHeader.restoreState(config.readEntry('Header', self.horizontalHeader.saveState))
    end
end

#--------------------------------------------------------------------
#--------------------------------------------------------------------
#
#
#
class MainWindow < KDE::MainWindow
    def initialize
        super(nil)

        setCaption(APP_NAME)
        @actions = KDE::ActionCollection.new(self)
        Qt::TextCodec::setCodecForTr(Qt::TextCodec::codecForName("utf-8"));

        createWidget
        createToolBar
        createMenu
        readSettings
        setAutoSaveSettings
    end

    def createMenu
         # file menu
        quitAction = @actions.addNew('Quit', self, \
            { :icon => 'exit', :shortCut => 'Ctrl+Q', :triggered => :close })
        openAction = @actions.addNew('Open Zip file', self, \
            { :icon => 'open-file', :shortCut => 'Ctrl+O', :triggered => :openFile })
        fileMenu = KDE::Menu.new(i18n('&File'), self)
        fileMenu.addAction(openAction)
        fileMenu.addSeparator
        fileMenu.addAction(quitAction)

        # extract menu
        extractAllAction = @actions.addNew('Extract All', self, \
            { :icon => 'extract', :shortCut => 'Ctrl+X', :triggered => :extractAll })
        extractAllHereAutoAction = @actions.addNew('Extract All Here Auto', self, \
            { :icon => 'extract', :shortCut => 'Ctrl+Shift+X', :triggered => :extractAllHereAuto })
        editMenu = KDE::Menu.new(i18n('Extract'), self)
        editMenu.addAction(extractAllAction)
        editMenu.addAction(extractAllHereAutoAction)

        # insert menus in MenuBar
        menu = KDE::MenuBar.new
        menu.addMenu( fileMenu )
        menu.addMenu( editMenu )
        setMenuBar(menu)
    end

    def createToolBar
    end

    def createWidget
        @fileTable = FileTable.new
        setCentralWidget(@fileTable)
    end



    #------------------------------------
    #
    # virtual slot
    def closeEvent(ev)
        writeSettings
        super(ev)
        $config.sync    # important!  qtruby can't invoke destructor properly.
    end


    GroupName = "MainWindow"
    def readSettings
        config = $config.group(GroupName)
        @actions.readSettings
    end

    def writeSettings
        config = $config.group(GroupName)
        @actions.writeSettings
        @fileTable.writeSettings
    end
        
    
    #------------------------------------
    #
    #
    slots :openFile
    def openFile
        # select zip file.
        fileName = KDE::FileDialog::getOpenFileName()
        return if !fileName || fileName.empty?
        unless File.exist?(fileName) then
            KDE::MessageBox.error(self, "#{fileName} is not exist.")
            return
        end
        
        begin
            @zipFile = Zip::ZipFile.open(fileName)
        rescue Zip::ZipError
            KDE::MessageBox.error(self, "#{fileName} is not zip file.")
            return
        end
        fileItems = @zipFile.entries.map do |e|
            FileItem.new(e)
        end
        @fileTable.setFiles(fileItems)
    end

    slots :extractAll
    def extractAll
        dirName = KDE::FileDialog::getExistingDirectory()
        extractToAll(dirName)
    end
    
    slots :extractAllHereAuto
    def extractAllHereAuto
        dirName = File.dirname(@zipFile.name)
        dirName = Dir.pwd if dirName.empty?
        unless unzipOnlyOneDirOrFile? then
            # make directory name from file name.
            rootDir = File.dirname(@zipFile.name)
            basename = File.basename(@zipFile.name)
            if File.extname(basename) != ".zip" then
                basename += ".dir"
            end
            dirName = File.join(rootDir, basename)
            while File.exist?(dirName) and File.file?(dirName) do
                if dirName =~ /\.dir$/ then
                    dirName += ".00"
                else
                    dirName.succ!
                end
            end
        end
        extractToAll(dirName)
    end

    def unzipOnlyOneDirOrFile?
        return true if @zipFile.count == 1

        topDir = nil
        @zipFile.entries.each do |e|
            name = e.name.toutf8
            if e.file? then
                dir = File.dirname(name).split(File::SEPARATOR)[0]
                return false if topDir and topDir != dir
                topDir = dir
            end
        end
        true
    end

    def extractToAll(dirName)
        return unless dirName && !dirName.empty?

        skipAll = false
        overWriteAll = false
        @zipFile.entries.each do |e|
            name = e.name.toutf8
            fname = File.join(dirName, name)
            if e.file? then
                dir = File.dirname(fname)
                FileUtils.mkdir_p(dir)
                skip = false
                if File.exist?(fname) then
                    if skipAll then
                        skip = true
                    elsif overWriteAll then
                        File.delete(fname)
                    else
                        OverWriteDlg.ask(self, fname)
                        case OverWriteDlg.selectedButton
                        when KDE::Dialog::Yes
                            File.delete(fname)
                        when KDE::Dialog::No
                            skip = true
                        when KDE::Dialog::User2 # yes to all
                            overWriteAll = true
                            File.delete(fname)
                        when KDE::Dialog::User1 # No to all
                            skip = true
                            skipAll = true
                        else # cancel
                            return
                        end
                    end
                end
                e.extract(fname) unless skip
            end
        end
    end
end
#------------------------------------------------------------------------------
#
#    main start
#

about = KDE::AboutData.new(APP_NAME, nil, KDE::ki18n(APP_NAME), APP_VERSION,
                            KDE::ki18n('sjis unzip with KDE GUI.')
                           )
about.addLicenseTextFile(APP_DIR + '/MIT-LICENSE')
KDE::CmdLineArgs.init(ARGV, about)

$app = KDE::Application.new
$config = KDE::Global::config
win = MainWindow.new
$app.setTopWidget(win)

win.show
$app.exec
