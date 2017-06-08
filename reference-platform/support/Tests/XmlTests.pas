unit XmlTests;

{
Copyright (c) 2011+, HL7 and Health Intersections Pty Ltd (http://www.healthintersections.com.au)
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
 * Neither the name of HL7 nor the names of its contributors may be used to
   endorse or promote products derived from this software without specific
   prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 'AS IS' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
}


{$DEFINE DIFF}

interface

Uses
  Windows, SysUtils, Classes, Soap.EncdDecd, ShellApi,
  StringSupport, GuidSupport, BytesSupport, EncodeSupport, TextUtilities, FileSupport,
  AdvObjects, AdvGenerics, AdvStringLists, AdvCSVExtractors, AdvFiles,
  MXML, XmlPatch, DUnitX.TestFramework;

Type
  XmlParserTestCaseAttribute = class (CustomTestCaseSourceAttribute)
  protected
    function GetCaseInfoArray : TestCaseInfoArray; override;
  end;

  [TextFixture]
  TXmlParserTests = Class (TObject)
  Published
    [XmlParserTestCase]
    procedure ParserTest(Name : String);
  End;

  XmlPatchTestCaseAttribute = class (CustomTestCaseSourceAttribute)
  protected
    function GetCaseInfoArray : TestCaseInfoArray; override;
  end;

  [TextFixture]
  TXmlPatchTests = Class (TObject)
  Private
    tests : TMXmlDocument;
    engine : TXmlPatchEngine;
  Published
    [SetupFixture] procedure setup;
    [TearDownFixture] procedure teardown;

    [XmlPatchTestCase]
    procedure PatchTest(Name : String);
  End;

function CheckXMLIsSame(filename1, filename2 : String; var msg : string) : boolean;

var
  showdiff : boolean = true;

implementation

uses
  IdGlobalProtocols;

function PadString(const AStr: String; AWidth: Integer; APadChar: Char; APadLeft: Boolean): String;
var
  i: Integer;
begin
  if Length(AStr) >= AWidth then
    Result := AStr
  else
  begin
    SetLength(Result, AWidth - length(AStr));
    for i := 1 to length(result) - length(AStr) do
      result[i] := APadChar;
    if APadLeft then
      result := result+AStr
    else
      result := AStr+result;
  end;
end;


function MakeXmlPretty(ASrc: String): String;
var
  i: Integer;
  l: Integer;
  LLevelIsSimple: Boolean;
  b : TStringBuilder;
begin
  Result := '';
  b := TStringBuilder.Create;
  try
    l := -1;
    LLevelIsSimple := False;
    for i := 1 to length(ASrc) do
      begin
      if ASrc[i] = '<' then
        begin
        if (i < length(ASrc)) and (ASrc[i + 1] = '?') then
          begin
          b.Append(ASrc[i]);
          end
        else if (i < length(ASrc)) and (ASrc[i + 1] = '/') then
          begin
          if not LLevelIsSimple then
            begin
            b.append(#13#10 + PadString('', l * 2, ' ', False) + ASrc[i]);
            end
          else
            begin
            b.append(ASrc[i]);
            end;
          dec(l);
          LLevelIsSimple := False;
          end
        else if (i < length(ASrc)) and (ASrc[i + 1] = '!') then
        begin
          b.append(#13#10 + PadString('', l * 2, ' ', False) + ASrc[i])
        end
        else
          begin
          inc(l);
          LLevelIsSimple := True;
          if l <> 0 then
            begin
            b.append(#13#10 + PadString('', l * 2, ' ', False) + ASrc[i]);
            end
          else
            begin
            If (i = 1) Or ((i > 1) And ((ASrc[i - 1] = #13) Or (ASrc[i-1] =  #10))) Then
              begin
              b.append(ASrc[i]);
              end
            else
              begin
              b.append(#13#10 + ASrc[i]);
              end;
            end;
          end;
        end
      else
        begin
        If (ASrc[i] = '>') And ( (ASrc[i-1] = '/') Or (ASrc[i-1] = '?') Or (ASrc[i-1] = '-')) Then
          begin
          b.append(ASrc[i]);
          If (ASrc[i-1] = '?') or (ASrc[i-1] = '-') Then
            begin
            b.append(#13#10);
            end;
          if ASrc[i-1] = '/' then
            begin
            dec(l);
            LLevelIsSimple := False;
            end;
          end
        Else If Not ((ASrc[i] = #9) Or (ASrc[i] = #10) Or (ASrc[i] = #13)) Then
          begin
          if LLevelIsSimple or (ASrc[1] <> ' ') then
            begin
            b.append(ASrc[i]);
            end;
          end;
        end
      end;
    Result := b.ToString;
  finally
    b.free;
  end;
end;

function normalise(text : String) : String;
begin
  result := text.Trim.replace(#13, ' ').replace(#10, ' ').replace(#9, ' ');
  while result.Contains('  ') do
    result := result.Replace('  ', ' ');
end;

function unbase64(text : String) : TBytes;
begin
  result := DecodeBase64(AnsiString(text));
end;

function CompareAttributes(path : String; src, tgt : TMXmlElement) : string;
var
//  i : integer;
//  sa, ta : IXMLDOMNode;
//  sn : String;
  b1, b2 : TBytes;
  a, b : TMXmlAttribute;
  s : String;
begin
  result := '';
  for s in src.Attributes.Keys do
  begin
    if not ((s = 'xmlns') or s.StartsWith('xmlns:')) then
    begin
      a := src.Attributes[s];
      if not tgt.Attributes.TryGetValue(s, b) then
        exit('Attributes differ at '+path+': missing attribute '+s);
      if normalise(a.value) <> normalise(b.value) then
      begin
        b1 := unBase64(a.value);
        b2 := unBase64(b.value);
        if not sameBytes(b1, b2) then
          exit('Attributes differ at '+path+': value '+normalise(a.value) +'/'+ normalise(b.value));
      end;
    end;
  end;
  for s in tgt.Attributes.Keys do
  begin
    if not ((s = 'xmlns') or s.StartsWith('xmlns:')) then
    begin
      a := tgt.Attributes[s];
      if not src.Attributes.TryGetValue(s, b) then
        exit('Attributes differ at '+path+': missing attribute '+s);
      if normalise(a.value) <> normalise(b.value) then
      begin
        b1 := unBase64(a.value);
        b2 := unBase64(b.value);
        if not sameBytes(b1, b2) then
          exit('Attributes differ at '+path+': value '+normalise(a.value) +'/'+ normalise(b.value));
      end;
    end;
  end;
end;

function skipBlankText(node : TMXmlElement) : TMXmlElement;
begin
  while (node <> nil) and (((node.nodeType = ntText) and StringIsWhitespace(node.text)) or (node.nodeType = ntComment)) do
    node := node.next;
  result := node;
end;

function CompareElements(path : String; e1, e2 : TMXmlElement) : String;
var
  c1, c2 : TMXmlElement;
  s : String;
begin
  if e1.namespaceURI <> e2.namespaceURI then
    exit('Namespaces differ at '+path+': '+e1.namespaceURI+'/'+e2.namespaceURI);
  if e1.localName <> e2.localName then
    exit('Names differ at '+path+': '+e1.localName+'/'+e2.localName);
  path := path + '/'+e1.localName;
  s := compareAttributes(path, e1, e2);
  if (s <> '') then
    exit(s);

  c1 := e1.first;
  c2 := e2.first;
  c1 := skipBlankText(c1);
  c2 := skipBlankText(c2);
  while (c1 <> nil) and (c2 <> nil) do
  begin
    if (c1.nodeType <> c2.nodeType) then
      exit('node type mismatch in children of '+path+': '+inttostr(ord(e1.nodeType))+'/'+inttostr(ord(e2.nodeType)));
    if (c1.nodeType = ntText) then
    begin
      if normalise(c1.text) <> normalise(c2.text) then
        exit('Text differs at '+path+': '+normalise(c1.text) +'/'+ normalise(c2.text));
    end
    else if (c1.nodeType = ntElement) then
    begin
      s := CompareElements(path, c1, c2);
      if (s <> '') then
        exit(s);
    end;

    c1 := skipBlankText(c1.next);
    c2 := skipBlankText(c2.next);
  end;
  if (c1 <> nil) then
    exit('node mismatch - more nodes in source in children of '+path);
  if (c2 <> nil) then
    exit('node mismatch - more nodes in target in children of '+path);
  result := '';
end;

function CompareXml(filename1, filename2 : String; var msg : string) : boolean;
var
  src, tgt : TMXmlDocument;
begin
  src := TMXmlParser.ParseFile(filename1, [xpResolveNamespaces]);
  try
    tgt := TMXmlParser.ParseFile(filename2, [xpResolveNamespaces]);
    try
      msg := CompareElements('', src.document, tgt.document);
      result := msg = '';
    finally
      tgt.Free;
    end;
  finally
    src.free;
  end
end;

function CheckXMLIsSame(filename1, filename2 : String; var msg : string) : boolean;
{$IFDEF DIFF}
var
  x1, x2, f1, f2, cmd : String;
{$ENDIF}
begin
  result := compareXML(filename1, filename2, msg);
{$IFDEF DIFF}
  if not result and showdiff then
  begin
    showdiff := false;
    x1 := FileToString(filename1 {$IFDEF UNICODE}, TEncoding.UTF8 {$ENDIF});
    x2 := FileToString(filename2 {$IFDEF UNICODE}, TEncoding.UTF8 {$ENDIF});
    x1 := MakeXmlPretty(x1);
    x2 := MakeXmlPretty(x2);
    x1 := x1.Replace('&#39;', '''').Replace('&quot;', '"');
    x2 := x2.Replace('&#39;', '''').Replace('&quot;', '"');

    f1 := MakeTempFilename +'-source.xml';
    f2 := MakeTempFilename +'-dest.xml';
    StringToFile(x1, f1{$IFDEF UNICODE}, TEncoding.UTF8{$ENDIF});
    StringToFile(x2, f2{$IFDEF UNICODE}, TEncoding.UTF8{$ENDIF});
    cmd := f1+' '+f2;
    ShellExecute(0, 'open', '"C:\Program Files (x86)\WinMerge\WinMergeU.exe"', PChar(cmd), PChar(ExtractFilePath(f1)), SW_MAXIMIZE);
  end;
{$ENDIF}
end;


{ TXmlTests }


{ XmlPatchTestCaseAttribute }

function XmlPatchTestCaseAttribute.GetCaseInfoArray: TestCaseInfoArray;
var
  tests : TMXmlDocument;
  test : TMXmlElement;
  i : integer;
  s : String;
begin
  tests := TMXmlParser.ParseFile('C:\work\fhirserver\tests\xml-patch-tests.xml', [xpResolveNamespaces]);
  try
    test := tests.document.first;
    i := 0;
    while test <> nil do
    begin
      if test.Name = 'case' then
      begin
        s := test.attribute['name'];
        SetLength(result, i+1);
        result[i].Name := s;
        SetLength(result[i].Values, 1);
        result[i].Values[0] := s;
        inc(i);
      end;
      test := test.Next;
    end;
  finally
    tests.Free;
  end;
end;

{ TXmlPatchTests }

procedure TXmlPatchTests.PatchTest(Name: String);
var
  test, target, patch, error, patched, outcome : TMXmlElement;
  s : String;
  ok : boolean;
begin
  test := tests.document.first;
  while test <> nil do
  begin
    if (test.Name = 'case') and (name = test.attribute['name']) then
    begin
      target := test.element('target');
      patch := test.element('patch');
      error := test.element('error');
      patched := test.element('patched');

      if (error <> nil) then
        Assert.WillRaiseWithMessage(
          procedure begin
            engine.execute(tests, target, patch);
          end, Exception, error.text)
      else
      begin
        engine.execute(tests, target, patch);
        StringToFile(target.first.ToXml(true), 'c:\temp\outcome.xml', TEncoding.UTF8);
        StringToFile(patched.first.ToXml(true), 'c:\temp\patched.xml', TEncoding.UTF8);
        ok := CheckXMLIsSame('c:\temp\patched.xml', 'c:\temp\outcome.xml', s);
        Assert.IsTrue(ok, s);
      end;
    end;
    test := test.Next;
  end;
end;

procedure TXmlPatchTests.setup;
begin
  tests := TMXmlParser.ParseFile('C:\work\org.hl7.fhir\build\tests\patch\xml-patch-tests.xml', [xpResolveNamespaces, xpDropWhitespace]);
  engine := TXmlPatchEngine.Create;
end;

procedure TXmlPatchTests.teardown;
begin
  engine.Free;
  tests.Free;
end;

{ TXmlParserTests }

procedure TXmlParserTests.ParserTest(Name: String);
var
  xml : TMXmlElement;
begin
  xml := TMXmlParser.parseFile(name, []);
  try
    Assert.Pass();
  finally
    xml.Free;
  end;
end;

{ XmlParserTestCaseAttribute }

function XmlParserTestCaseAttribute.GetCaseInfoArray: TestCaseInfoArray;
var
  sl : TStringlist;
  sr : TSearchRec;
  s : String;
  i : integer;
begin
  sl := TStringList.create;
  try
    if FindFirst('C:\work\fhirserver\reference-platform\support\Tests\*.xml', faAnyFile, SR) = 0 then
    repeat
      s := sr.Name;
      sl.Add(sr.Name);
    until FindNext(SR) <> 0;
    setLength(result, sl.Count);
    for i := 0 to sl.Count - 1 do
    begin
      result[i].Name := sl[i];
      SetLength(result[i].Values, 1);
      result[i].Values[0] := 'C:\work\fhirserver\reference-platform\support\Tests\' + sl[i];
    end;
  finally
    sl.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TXmlParserTests);
  TDUnitX.RegisterTestFixture(TXmlPatchTests);
end.
